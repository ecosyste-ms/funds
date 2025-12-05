require "test_helper"

class ProjectAllocationEventTest < ActiveSupport::TestCase
  setup do
    @fund = create(:fund)
    @allocation = create(:allocation, fund: @fund)
    @project = create(:project)
    @project_allocation = create(:project_allocation, project: @project, fund: @fund, allocation: @allocation)
  end

  test "belongs to project_allocation" do
    event = ProjectAllocationEvent.new(
      project_allocation: @project_allocation,
      fund: @fund,
      allocation: @allocation,
      event_type: 'payout_started',
      status: 'success'
    )
    assert event.valid?
    assert_equal @project_allocation, event.project_allocation
  end

  test "requires event_type" do
    event = ProjectAllocationEvent.new(
      project_allocation: @project_allocation,
      fund: @fund,
      allocation: @allocation,
      status: 'success'
    )
    assert_not event.valid?
    assert_includes event.errors[:event_type], "can't be blank"
  end

  test "validates status inclusion" do
    event = ProjectAllocationEvent.new(
      project_allocation: @project_allocation,
      fund: @fund,
      allocation: @allocation,
      event_type: 'payout_started',
      status: 'invalid'
    )
    assert_not event.valid?
    assert_includes event.errors[:status], "is not included in the list"
  end

  test "allows nil status" do
    event = ProjectAllocationEvent.new(
      project_allocation: @project_allocation,
      fund: @fund,
      allocation: @allocation,
      event_type: 'payout_started',
      status: nil
    )
    assert event.valid?
  end

  test "success? returns true for success status" do
    event = ProjectAllocationEvent.new(status: 'success')
    assert event.success?
    assert_not event.error?
  end

  test "error? returns true for error status" do
    event = ProjectAllocationEvent.new(status: 'error')
    assert event.error?
    assert_not event.success?
  end

  test "pending? returns true for pending status" do
    event = ProjectAllocationEvent.new(status: 'pending')
    assert event.pending?
  end

  test "errors scope returns only error events" do
    create_event('payout_started', 'success')
    create_event('payout_failed', 'error')
    create_event('payout_completed', 'success')

    errors = ProjectAllocationEvent.errors
    assert_equal 1, errors.count
    assert_equal 'error', errors.first.status
  end

  test "successes scope returns only success events" do
    create_event('payout_started', 'success')
    create_event('payout_failed', 'error')
    create_event('payout_completed', 'success')

    successes = ProjectAllocationEvent.successes
    assert_equal 2, successes.count
  end

  test "for_type scope filters by event type" do
    create_event('payout_started', 'success')
    create_event('payout_completed', 'success')

    events = ProjectAllocationEvent.for_type('payout_started')
    assert_equal 1, events.count
    assert_equal 'payout_started', events.first.event_type
  end

  test "for_fund scope filters by fund" do
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

    events = ProjectAllocationEvent.for_fund(@fund)
    assert_equal 1, events.count
    assert_equal @fund.id, events.first.fund_id
  end

  test "recent scope orders by created_at desc" do
    event1 = create_event('payout_started', 'success')
    event2 = create_event('payout_completed', 'success')

    events = ProjectAllocationEvent.recent
    assert_equal event2.id, events.first.id
    assert_equal event1.id, events.last.id
  end

  test "stores metadata as json" do
    event = create_event('payout_started', 'success', metadata: { amount_cents: 5000, payout_method: 'OSC' })
    event.reload

    assert_equal 5000, event.metadata['amount_cents']
    assert_equal 'OSC', event.metadata['payout_method']
  end

  test "project returns the associated project" do
    event = create_event('payout_started', 'success')
    assert_equal @project, event.project
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
