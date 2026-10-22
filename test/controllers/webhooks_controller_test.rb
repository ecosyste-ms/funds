require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    SyncInviteWorker.clear
  end

  teardown do
    SyncInviteWorker.clear
  end

  test "paid expense webhook syncs status and displays payment" do
    project = create(:project, funding_rejected: false)
    project_allocation = create(:project_allocation, project: project, paid_at: Time.current)
    invitation = create(:invitation, project_allocation: project_allocation, member_invitation_id: '277913', status: 'APPROVED', data: {
      'id' => 'expense-id', 'status' => 'PENDING', 'draftKey' => 'draft-key',
      'aggregated_allocation_ids' => [project_allocation.id]
    })
    request = stub_request(:post, /graphql\/v2/).with { |req| JSON.parse(req.body).dig('variables', 'id') == '277913' }
      .to_return(body: { data: { expense: { id: 'expense-id', legacyId: 277913, status: 'PAID' } } }.to_json)

    post '/webhooks', params: { type: 'collective.expense.paid', data: { expense: { id: 277913 } } }, as: :json

    assert_response :success
    assert_equal [[invitation.id]], SyncInviteWorker.jobs.map { |job| job['args'] }
    SyncInviteWorker.drain
    assert_requested request
    assert_equal 'PAID', invitation.reload.status
    assert_equal 'PAID', invitation[:status]
    assert_equal 'PAID', invitation.data['status']
    assert_equal 'draft-key', invitation.data['draftKey']
    assert_equal [project_allocation.id], invitation.data['aggregated_allocation_ids']
    assert_equal 'expense_synced', invitation.events.last.event_type

    get project_path(project)

    assert_response :success
    assert_select '.badge', text: 'Paid'
    assert_select 'a', text: '#277913'
    assert_select '.badge', text: 'Invitation Pending', count: 0
  end

  test "expense status changes schedule a sync" do
    invitation = create(:invitation, member_invitation_id: '277913')
    %w[updated approved unapproved rejected unpaid processing scheduledForPayment reApprovalRequested error invite.declined].each do |event|
      SyncInviteWorker.clear
      post '/webhooks', params: { type: "collective.expense.#{event}", data: { expense: { id: 277913 } } }, as: :json
      assert_response :success
      assert_equal [[invitation.id]], SyncInviteWorker.jobs.map { |job| job['args'] }, event
    end
  end

  test "shared expense webhook refreshes every member and the public funding totals" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    first = create(:project_allocation, fund: fund, allocation: allocation, amount_cents: 1200)
    second = create(:project_allocation, fund: fund, allocation: allocation, amount_cents: 3400)
    unrelated = create(:project_allocation, fund: fund, allocation: create(:allocation, fund: fund))
    create(:invitation, project_allocation: second, status: 'DRAFT')
    create(:invitation, project_allocation: first, member_invitation_id: '277914', status: 'DRAFT',
      data: { 'aggregated_allocation_ids' => [first.id, second.id, unrelated.id] })
    request = stub_request(:post, /graphql\/v2/)
      .with { |req| JSON.parse(req.body).dig('variables', 'id') == '277914' }
      .to_return(body: { data: { expense: { id: 'shared-expense', status: 'PAID' } } }.to_json)

    post '/webhooks', params: { type: 'collective.expense.paid', data: { expense: { id: 277914 } } }, as: :json
    assert_response :success
    SyncInviteWorker.drain
    assert_requested request
    assert first.reload.funded?
    assert second.reload.funded?
    assert_not unrelated.reload.funded?

    queries = record_select_queries do
      get api_v1_fund_projects_path(fund_slug: fund.slug)
    end
    assert_response :success
    assert_equal 2, response.parsed_body['funded_projects_count']
    assert_equal [12.0, 34.0], response.parsed_body['projects'].map { |row| row['allocated_amount']['value'] }.sort
    assert queries.none? { |sql| sql.include?('"invitations"') }, 'funding reads must use stored flags'

    stub_request(:post, /graphql\/v2/)
      .with { |req| JSON.parse(req.body).dig('variables', 'id') == '277914' }
      .to_return(body: { data: { expense: { id: 'shared-expense', status: 'PENDING' } } }.to_json)
    post '/webhooks', params: { type: 'collective.expense.unapproved', data: { expense: { id: 277914 } } }, as: :json
    assert_response :success
    SyncInviteWorker.drain
    assert_not first.reload.funded?
    assert_not second.reload.funded?

    get api_v1_fund_projects_path(fund_slug: fund.slug)
    assert_response :success
    assert_equal 0, response.parsed_body['funded_projects_count']
    assert_empty response.parsed_body['projects']
  end

  test "missing and unknown expense ids do not sync a local invitation" do
    create(:invitation, member_invitation_id: nil)
    [{}, { data: {} }, { data: { expense: {} } }, { data: { expense: { id: 999999 } } }].each do |payload|
      post '/webhooks', params: payload.merge(type: 'collective.expense.paid'), as: :json
      assert_response :success
      assert_empty SyncInviteWorker.jobs
    end
  end
end
