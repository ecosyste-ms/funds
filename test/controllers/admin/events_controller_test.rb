require "test_helper"

class Admin::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund = create(:fund)
    @allocation = create(:allocation, fund: @fund)
    @project = create(:project)
    @project_allocation = create(:project_allocation, project: @project, fund: @fund, allocation: @allocation)
  end

  test "should get index" do
    create_event('payout_started', 'success')
    create_event('payout_completed', 'success')

    get admin_events_url
    assert_response :success
    assert_select ".card", minimum: 2
  end

  test "should filter by fund" do
    other_fund = create(:fund)
    other_allocation = create(:allocation, fund: other_fund)
    other_pa = create(:project_allocation, fund: other_fund, allocation: other_allocation, project: @project)

    create_event('payout_started', 'success')
    ProjectAllocationEvent.create!(
      project_allocation: other_pa,
      fund: other_fund,
      allocation: other_allocation,
      event_type: 'payout_started',
      status: 'success'
    )

    get admin_events_url(fund_id: @fund.id)
    assert_response :success
    assert_select ".card .badge.bg-secondary", text: "Payout started", count: 1
  end

  test "should filter by event type" do
    create_event('payout_started', 'success')
    create_event('payout_completed', 'success')

    get admin_events_url(event_type: 'payout_started')
    assert_response :success
    assert_select ".card .badge.bg-secondary", text: "Payout started", count: 1
  end

  test "should filter by status" do
    create_event('payout_started', 'success')
    create_event('payout_failed', 'error')

    get admin_events_url(status: 'error')
    assert_response :success
    assert_select ".badge.bg-danger", text: "Error", count: 1
  end

  test "should show metadata when present" do
    create_event('payout_started', 'success', metadata: { amount_cents: 5000 })

    get admin_events_url
    assert_response :success
    assert_select "details summary", text: "View metadata"
  end

  def create_event(event_type, status, metadata: {})
    ProjectAllocationEvent.create!(
      project_allocation: @project_allocation,
      fund: @fund,
      allocation: @allocation,
      event_type: event_type,
      status: status,
      metadata: metadata
    )
  end
end
