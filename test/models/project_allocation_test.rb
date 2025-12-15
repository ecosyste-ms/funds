require "test_helper"

class ProjectAllocationTest < ActiveSupport::TestCase
  test "send_expense_invite returns skipped hash when funding is rejected" do
    project = create(:project, funding_rejected: true, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil)

    result = pa.send_expense_invite

    assert_equal({ skipped: 'funding_rejected' }, result)
  end

  test "send_expense_invite returns skipped hash when has approved funding source" do
    funding_source = create(:funding_source, platform: 'github.com')
    project = create(:project, owner: { 'email' => 'test@example.com' }, funding_source: funding_source)
    pa = create(:project_allocation, project: project, funding_source: funding_source)

    result = pa.send_expense_invite

    assert_equal({ skipped: 'has_approved_funding_source' }, result)
  end

  test "send_expense_invite returns skipped hash when no contact email" do
    project = create(:project, owner: nil)
    pa = create(:project_allocation, project: project, funding_source: nil)

    result = pa.send_expense_invite

    assert_equal({ skipped: 'no_contact_email' }, result)
  end

  test "send_expense_invite returns skipped hash when invitation already sent" do
    project = create(:project, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil)
    create(:invitation, project_allocation: pa, member_invitation_id: 12345)

    result = pa.send_expense_invite

    assert_equal 'invitation_already_sent', result[:skipped]
    assert_equal 12345, result[:invitation_id].to_i
  end

  test "send_expense_invite returns skipped hash when already paid" do
    project = create(:project, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil, paid_at: Time.now)

    result = pa.send_expense_invite

    assert_equal({ skipped: 'already_paid' }, result)
  end

  test "payout logs skipped event with metadata when amount below funding source minimum" do
    funding_source = create(:funding_source, platform: 'github.com', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
    project = create(:project, owner: { 'email' => 'test@example.com' }, funding_source: funding_source)
    pa = create(:project_allocation, project: project, funding_source: funding_source, amount_cents: 5000)

    pa.payout

    event = pa.events.find_by(event_type: 'payout_skipped')
    assert_not_nil event
    assert_equal 'success', event.status
    assert_equal 'Amount below funding source minimum', event.message
    assert_equal 5000, event.metadata['amount_cents']
    assert_equal 10000, event.metadata['minimum_cents']
  end
end
