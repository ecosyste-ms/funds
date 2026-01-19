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

  test "payout falls back to email invite when amount below funding source minimum" do
    funding_source = create(:funding_source, platform: 'github.com', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
    project = create(:project, owner: { 'email' => 'test@example.com' }, funding_source: funding_source)
    pa = create(:project_allocation, project: project, funding_source: funding_source, amount_cents: 5000)

    # Stub the OC API call
    stub_request(:post, /opencollective/).to_return(
      status: 200,
      body: { data: { draftExpenseAndInviteUser: { id: '123', legacyId: 456, status: 'DRAFT', draftKey: 'abc' } } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    pa.payout

    # Should log the below_minimum event first
    below_min_event = pa.events.find_by(event_type: 'payout_below_minimum')
    assert_not_nil below_min_event
    assert_equal 'success', below_min_event.status
    assert_equal 5000, below_min_event.metadata['amount_cents']
    assert_equal 10000, below_min_event.metadata['minimum_cents']
  end

  test "payout_via_email_invite skips when funding rejected" do
    project = create(:project, funding_rejected: true, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil)

    pa.payout_via_email_invite

    assert_nil pa.paid_at
  end

  test "payout_via_email_invite skips when already paid" do
    project = create(:project, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil, paid_at: Time.now)

    pa.payout_via_email_invite

    # Should not create any new events (already paid)
    assert_equal 0, pa.events.where(event_type: 'payout_completed').count
  end

  test "payout_via_email_invite logs error when no contact email" do
    project = create(:project, owner: nil)
    pa = create(:project_allocation, project: project, funding_source: nil)

    pa.payout_via_email_invite

    event = pa.events.find_by(event_type: 'payout_skipped')
    assert_not_nil event
    assert_equal 'error', event.status
    assert_equal 'No contact email for email fallback', event.message
  end

  test "send_expense_invite_fallback allows sending even with approved funding source" do
    funding_source = create(:funding_source, platform: 'github.com')
    project = create(:project, owner: { 'email' => 'test@example.com' }, funding_source: funding_source)
    pa = create(:project_allocation, project: project, funding_source: funding_source)

    # send_expense_invite would return skipped for approved funding source
    regular_result = pa.send_expense_invite
    assert_equal({ skipped: 'has_approved_funding_source' }, regular_result)

    # Stub the OC API call
    stub_request(:post, /opencollective/).to_return(
      status: 200,
      body: { data: { draftExpenseAndInviteUser: { id: '123', legacyId: 456, status: 'DRAFT', draftKey: 'abc' } } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    # send_expense_invite_fallback should NOT skip for approved funding source
    fallback_result = pa.send_expense_invite_fallback
    # Should not return the 'has_approved_funding_source' skip - should return an Invitation
    refute_equal({ skipped: 'has_approved_funding_source' }, fallback_result)
    assert fallback_result.is_a?(Invitation)
  end

  test "send_expense_invite_fallback returns skipped hash when funding rejected" do
    project = create(:project, funding_rejected: true, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil)

    result = pa.send_expense_invite_fallback

    assert_equal({ skipped: 'funding_rejected' }, result)
  end

  test "send_expense_invite_fallback returns skipped hash when no contact email" do
    project = create(:project, owner: nil)
    pa = create(:project_allocation, project: project, funding_source: nil)

    result = pa.send_expense_invite_fallback

    assert_equal({ skipped: 'no_contact_email' }, result)
  end

  test "send_expense_invite_fallback returns skipped hash when already paid" do
    project = create(:project, owner: { 'email' => 'test@example.com' })
    pa = create(:project_allocation, project: project, funding_source: nil, paid_at: Time.now)

    result = pa.send_expense_invite_fallback

    assert_equal({ skipped: 'already_paid' }, result)
  end

  test "minimum_funding_source_amount_met? returns true when amount exceeds minimum" do
    funding_source = create(:funding_source, platform: 'github.com', github_sponsors: { 'minimum_sponsorship_amount' => 50 })
    project = create(:project, owner: { 'email' => 'test@example.com' }, funding_source: funding_source)
    pa = create(:project_allocation, project: project, funding_source: funding_source, amount_cents: 10000)

    assert pa.minimum_funding_source_amount_met?
  end

  test "minimum_funding_source_amount_met? returns false when amount below minimum" do
    funding_source = create(:funding_source, platform: 'github.com', github_sponsors: { 'minimum_sponsorship_amount' => 100 })
    project = create(:project, owner: { 'email' => 'test@example.com' }, funding_source: funding_source)
    pa = create(:project_allocation, project: project, funding_source: funding_source, amount_cents: 5000)

    refute pa.minimum_funding_source_amount_met?
  end
end
