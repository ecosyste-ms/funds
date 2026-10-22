require 'test_helper'
require 'rake'

class ContactSelectionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('funds:run_allocations')
    @fund = create(:fund, name: 'Example', slug: 'example')
    @allocation = create(:allocation, fund: @fund, year: Time.current.year, month: Time.current.month)
    @project = create(:project, url: 'https://github.com/example/project', owner: nil, packages: [
      { 'name' => '@fork/project', 'registry' => { 'name' => 'npmjs.org' }, 'maintainers' => [{ 'login' => 'fork', 'email' => 'fork@example.com' }] },
      { 'name' => 'project', 'registry' => { 'name' => 'npmjs.org' }, 'maintainers' => [{ 'login' => 'example', 'email' => 'example@example.com' }] }
    ])
    @pa = create(:project_allocation, project: @project, fund: @fund, allocation: @allocation, funding_source: nil, amount_cents: 5000)
  end

  test 'scheduled invitations leave ambiguous contacts for review without sending mail' do
    assert_no_difference(['Invitation.count', 'ActionMailer::Base.deliveries.count']) do
      Rake::Task['funds:run_allocations'].execute
    end

    event = @pa.events.find_by!(event_type: 'invitation_contact_unresolved')
    assert_equal 'pending', event.status
    assert_equal ['example@example.com', 'fork@example.com'], event.metadata['candidates'].map { |c| c['email'] }.sort
    assert_nil @pa.reload.paid_at
  end

  test 'a confirmed address is used by scheduled invitations without changing the candidates' do
    @project.confirm_contact_email!('confirmed@example.com')

    assert_difference('Invitation.count', 1) do
      assert_difference('ActionMailer::Base.deliveries.count', 1) do
        Rake::Task['funds:run_allocations'].execute
      end
    end

    assert_equal 'confirmed@example.com', @pa.reload.invitation.email
    assert_equal ['confirmed@example.com'], ActionMailer::Base.deliveries.last.to
    assert_equal 2, @project.reload.contact_candidates.length
  end

  test 'aggregated below minimum fallback matches the funding recipient before sending an expense' do
    source = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/lpinca', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
    @pa.update!(funding_source: source)
    @project.update!(owner: { 'login' => 'websockets', 'email' => 'owner@example.com' }, commits: {
      'committers' => [{ 'name' => 'Luigi Pinca', 'login' => 'lpinca', 'email' => 'luigi@example.com', 'count' => 762 }]
    })
    request = stub_request(:post, /graphql\/v2/).with { |req|
      JSON.parse(req.body).dig('variables', 'expense', 'payee', 'email') == 'luigi@example.com'
    }.to_return(body: { data: { draftExpenseAndInviteUser: { id: 'expense', legacyId: 123, status: 'DRAFT' } } }.to_json)

    @allocation.payout

    assert_requested request, times: 1
    assert_equal 'luigi@example.com', @pa.reload.invitation.email
    assert_not_nil @pa.paid_at
  end

  test 'named recipient fallback does not send to a different top contributor or registry namesake' do
    source = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/recipient', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
    @pa.update!(funding_source: source)
    @project.update!(packages: [{ 'name' => 'project', 'registry' => { 'name' => 'npmjs.org' }, 'maintainers' => [
      { 'login' => 'recipient', 'email' => 'namesake@example.com' }
    ] }], commits: { 'committers' => [{ 'name' => 'Other', 'login' => nil, 'email' => 'other@example.com', 'count' => 166 }] })

    assert_no_difference('Invitation.count') { @allocation.payout }

    assert_not_requested :post, /graphql\/v2/
    assert_nil @pa.reload.paid_at
    assert @pa.events.exists?(event_type: 'payout_skipped')
  end

  test 'a collective remains the expense payee when no contact email is resolved' do
    source = create(:funding_source, platform: 'opencollective.com', url: 'https://opencollective.com/postcss', collective: { 'host' => 'evilmartians' })
    @pa.update!(funding_source: source)
    request = stub_request(:post, /graphql\/v2/).with { |req|
      body = JSON.parse(req.body)
      body['query'].include?('skipInvite: false') && body.dig('variables', 'expense', 'payee') == { 'slug' => 'postcss', 'isInvite' => true }
    }.to_return(body: { data: { draftExpenseAndInviteUser: { id: 'expense', legacyId: 124, status: 'DRAFT', draftKey: 'key', payee: { slug: 'postcss' } } } }.to_json)

    @allocation.payout

    assert_requested request, times: 1
    assert_not_nil @pa.reload.paid_at
    assert_nil @pa.invitation.email
    assert_no_difference('ActionMailer::Base.deliveries.count') { @pa.send_expense_invite_email }
    get project_path(@project)
    assert_response :success
    assert_select 'a', text: '#124'
  end

  test 'collective expense notifications do not use a previously inferred contact' do
    source = create(:funding_source, platform: 'opencollective.com', url: 'https://opencollective.com/postcss', collective: { 'host' => 'evilmartians' })
    @pa.update!(funding_source: source)
    original = create(:invitation, project_allocation: @pa, email: 'fork@example.com')
    stub_request(:post, /graphql\/v2/).to_return(body: {
      data: { draftExpenseAndInviteUser: { id: 'expense', legacyId: 127, status: 'DRAFT', draftKey: 'key' } }
    }.to_json)

    @allocation.payout

    assert_equal original.id, @pa.reload.invitation.id
    assert_no_difference('ActionMailer::Base.deliveries.count') { @pa.send_expense_invite_email }
  end

  test 'the allocation recipient takes precedence over the current project funding source' do
    source = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/original', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
    current = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/changed')
    @pa.update!(funding_source: source)
    @project.update!(funding_source: current, owner: { 'login' => 'changed', 'email' => 'changed@example.com' }, commits: {
      'committers' => [{ 'name' => 'Original', 'login' => 'original', 'email' => 'original@example.com', 'count' => 1 }]
    })
    request = stub_request(:post, /graphql\/v2/).with { |req|
      JSON.parse(req.body).dig('variables', 'expense', 'payee', 'email') == 'original@example.com'
    }.to_return(body: { data: { draftExpenseAndInviteUser: { id: 'expense', legacyId: 126, status: 'DRAFT' } } }.to_json)

    @allocation.payout

    assert_requested request, times: 1
    assert_equal 'original@example.com', @pa.reload.invitation.email
  end

  test 'an old unsent expense invitation keeps its token when a new recipient is selected' do
    original = create(:invitation, project_allocation: @pa, email: 'fork@example.com', accepted_at: Time.current)
    token = original.token
    @project.confirm_contact_email!('confirmed@example.com')
    stub_request(:post, /graphql\/v2/).to_return(body: {
      data: { draftExpenseAndInviteUser: { id: 'expense', legacyId: 125, status: 'DRAFT' } }
    }.to_json)

    assert_difference('Invitation.count', 1) { @allocation.payout }

    assert_equal 'fork@example.com', original.reload.email
    assert_equal token, original.token
    assert_nil original.member_invitation_id
    assert_equal 'confirmed@example.com', @pa.reload.invitation.email
    refute_equal token, @pa.invitation.token
  end
end
