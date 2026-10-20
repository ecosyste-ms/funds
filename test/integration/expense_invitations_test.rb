require "test_helper"
require "rake"

class ExpenseInvitationsTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('funds:run_allocations')
    @fund = create(:fund, name: 'Go', slug: 'go')
    @allocation = create(:allocation, fund: @fund, year: Time.current.year, month: Time.current.month, total_cents: 5000)
    @project = create(:project, funding_rejected: false, owner: { 'email' => 'maintainer@example.com' })
    @pa = create(:project_allocation, fund: @fund, allocation: @allocation, project: @project, funding_source: nil, amount_cents: 5000, created_at: Time.current)
  end

  test "scheduled allocation and payout reuse the invitation and its token" do
    Invitation.any_instance.stubs(:send_email)
    Rake::Task['funds:run_allocations'].execute
    original = @pa.reload.invitation
    token = original.token
    original.update!(accepted_at: Time.current)
    event_ids = original.events.ids
    request = stub_request(:post, /graphql\/v2/).to_return(body: {
      data: { draftExpenseAndInviteUser: { id: 'expense-id', legacyId: 285877, status: 'DRAFT', draftKey: 'draft-key' } }
    }.to_json)
    AllocationMailer.stubs(:github_sponsors_csv).returns(stub(deliver_now: true))

    assert_no_difference('Invitation.count') { Rake::Task['funds:payout'].execute }

    assert_requested request, times: 1
    assert_equal original.id, @pa.reload.invitation.id
    assert_equal token, original.reload.token
    assert_not_nil original.accepted_at
    assert_equal '285877', original.member_invitation_id
    assert_equal 'draft-key', original.draft_key
    assert_empty event_ids - original.events.ids
    assert original.events.exists?(event_type: 'expense_created')

    get invitation_path(token: token)
    assert_response :success
    get project_path(@project)
    assert_response :success
    assert_select 'a', text: '#285877'

    assert_no_difference('Invitation.count') { Rake::Task['funds:payout'].execute }
    assert_requested request, times: 1
  end

  test "project page selects the expense from existing duplicate invitations" do
    expense = create(:invitation, project_allocation: @pa, member_invitation_id: '285877', deleted_at: Time.current, status: 'DELETED', data: { 'status' => 'DRAFT' })
    local = create(:invitation, project_allocation: @pa, member_invitation_id: nil)
    local_event = @pa.log_event('invitation_created', invitation_record: local)
    expense_event = @pa.log_event('expense_deleted', invitation_record: expense)
    @pa.update!(paid_at: Time.current)

    assert_no_difference(['Invitation.count', 'ProjectAllocationEvent.count']) do
      get project_path(@project)
    end

    assert_response :success
    assert_select '.badge', text: 'Deleted'
    assert_select '.badge', text: 'Invitation Pending', count: 0
    assert_select 'a', text: '#285877'
    assert_equal expense.id, @pa.reload.invitation.id
    assert_equal expense.id, ProjectAllocation.where(id: @pa.id).includes(:invitation).first.invitation.id
    assert_equal local.id, local_event.reload.invitation_id
    assert_equal expense.id, expense_event.reload.invitation_id
    get invitation_path(token: local.token)
    assert_response :success
  end

  test "older local invitation does not hide the paid expense" do
    create(:invitation, project_allocation: @pa)
    expense = create(:invitation, project_allocation: @pa, member_invitation_id: '285877', status: 'PAID', data: { 'status' => 'PAID' })

    get project_path(@project)

    assert_response :success
    assert_select '.badge', text: 'Paid'
    assert_select 'a', text: '#285877'
    assert_equal expense.id, @pa.reload.invitation.id
    assert_equal expense.id, ProjectAllocation.where(id: @pa.id).includes(:invitation).first.invitation.id
    assert @pa.success?
  end

  test "a later expense preserves the earlier expense and its history" do
    source = create(:funding_source, platform: 'opencollective.com', url: 'https://opencollective.com/example', collective: { 'host' => 'other-host' })
    @pa.update!(funding_source: source)
    previous = create(:invitation, project_allocation: @pa, member_invitation_id: '285876', data: { 'id' => 'old-expense', 'status' => 'REJECTED' })
    token = previous.token
    event = @pa.log_event('expense_created', invitation_record: previous)
    stub_request(:post, /graphql\/v2/).to_return(body: {
      data: { draftExpenseAndInviteUser: { id: 'new-expense', legacyId: 285877, status: 'DRAFT' } }
    }.to_json)

    assert_difference('Invitation.count', 1) { @pa.payout }

    assert_equal '285876', previous.reload.member_invitation_id
    assert_equal 'old-expense', previous.data['id']
    assert_equal token, previous.token
    assert_equal previous.id, event.reload.invitation_id
    assert_equal '285877', @pa.reload.invitation.member_invitation_id
    get project_path(@project)
    assert_response :success
    assert_select 'a', text: '#285877'
  end

  %w[fallback collective vendor aggregated].each do |payout_type|
    test "#{payout_type} payout preserves the original invitation" do
      Invitation.any_instance.stubs(:send_email)
      @pa.send_invitation
      original = @pa.reload.invitation
      token = original.token
      original.update!(accepted_at: Time.current)
      source = create(:funding_source, platform: 'github.com', url: 'https://github.com/sponsors/example', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
      if payout_type == 'collective'
        source.update!(platform: 'opencollective.com', url: 'https://opencollective.com/example', collective: { 'host' => 'other-host' })
      elsif payout_type != 'fallback'
        source.update!(github_sponsors: { 'minimum_sponsorship_amount' => 1 })
      end
      @pa.update!(funding_source: source)
      vendor = create(:proxy_collective, name: source.url, website: source.url)
      ProxyCollective.stubs(:find_or_create_by_website).returns(vendor)
      ProxyCollective.any_instance.stubs(:set_payout_method)
      request = stub_request(:post, /graphql\/v2/).to_return do |req|
        query = JSON.parse(req.body)['query']
        key = query.include?('processExpense') ? 'processExpense' : query.include?('createExpense') ? 'createExpense' : 'draftExpenseAndInviteUser'
        { body: { data: { key => { id: 'expense-id', legacyId: 285877, status: 'DRAFT', draftKey: 'draft-key' } } }.to_json }
      end

      assert_no_difference('Invitation.count') do
        payout_type == 'aggregated' ? @allocation.payout : @pa.payout
      end

      assert_requested request, at_least_times: 1
      assert_equal original.id, @pa.reload.invitation.id
      assert_equal token, original.reload.token
      assert_not_nil original.accepted_at
      assert_equal '285877', original.member_invitation_id
      assert original.events.exists?(event_type: 'expense_created')
      assert_equal [@pa.id], original.data['aggregated_allocation_ids'] if payout_type == 'aggregated'
      get project_path(@project)
      assert_response :success
      assert_select 'a', text: '#285877'
    end
  end
end
