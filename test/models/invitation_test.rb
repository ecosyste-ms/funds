require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  require "test_helper"

  test "status uses the stored column when the response snapshot is stale" do
    invitation = create(:invitation, status: 'APPROVED', data: { 'status' => 'PENDING' })
    assert_equal 'APPROVED', invitation.reload.status
    assert invitation.project_allocation.success?
  end

  test "status supports older snapshots and local deletions" do
    invitation = create(:invitation, status: nil, data: { 'status' => 'PAID' })
    assert_equal 'PAID', invitation.status
    invitation.update!(deleted_at: Time.current)
    assert_equal 'DELETED', invitation.status
    assert_nil build(:invitation, status: nil, data: nil).status
  end

  test "legacy draft column does not expire an expense already submitted or paid" do
    travel_to Time.zone.local(2026, 10, 15) do
      %w[PENDING APPROVED PAID].each do |status|
        invitation = create(:invitation, status: 'DRAFT', data: { 'status' => status })
        invitation.project_allocation.update!(created_at: 2.months.ago)
        assert_equal status, invitation.reload.status
        refute invitation.expired?
      end
    end
  end

  test "approving and unapproving keeps the stored status and snapshot aligned" do
    invitation = create(:invitation, status: 'PENDING', data: { 'id' => 'expense-id', 'status' => 'PENDING', 'draftKey' => 'draft-key' })
    { 'APPROVE' => ['approve_expense', 'APPROVED'], 'UNAPPROVE' => ['unapprove_expense', 'PENDING'] }.each do |action, (method, status)|
      request = stub_request(:post, /graphql\/v2/).with { |req| JSON.parse(req.body).dig('variables', 'action') == action }
        .to_return(body: { data: { processExpense: { id: 'expense-id', status: status } } }.to_json)
      invitation.public_send(method)
      assert_requested request
      assert_equal status, invitation.reload.status
      assert_equal status, invitation[:status]
      assert_equal status, invitation.data['status']
      assert_equal 'draft-key', invitation.data['draftKey']
    end
  end

  test "token is unique" do
    # Stub SecureRandom.hex to force a duplicate token scenario
    SecureRandom.expects(:hex).twice.returns("duplicate_token", "unique_token")

    # Create the first invitation
    invitation1 = create(:invitation)
    assert_equal "duplicate_token", invitation1.token

    # Create the second invitation, which should resolve the collision and generate a unique token
    invitation2 = create(:invitation)
    assert_equal "unique_token", invitation2.token
  end

  test "token is generated before creation" do
    invitation = create(:invitation)
    assert_not_nil invitation.token
    assert_equal 32, invitation.token.length # SecureRandom.hex(16) generates a 32-character token
  end

  test "handles collisions by generating a new token" do
    SecureRandom.expects(:hex).twice.returns("duplicate_token", "unique_token")

    create(:invitation, token: "duplicate_token")
    invitation2 = create(:invitation)

    assert_equal "unique_token", invitation2.token
  end

  test "delete_expired continues past an invitation whose delete_expense raises" do
    create(:invitation, status: 'DRAFT')
    create(:invitation, status: 'DRAFT')

    Invitation.any_instance.stubs(:expired?).returns(true)
    Invitation.any_instance.expects(:delete_expense).twice.raises(JSON::ParserError, 'boom')

    assert_nothing_raised { Invitation.delete_expired }
  end

  test "delete_expense logs an error event when the response body is not JSON" do
    invitation = create(:invitation, data: { 'id' => 'ex_1', 'status' => 'DRAFT' })
    stub_request(:post, /graphql/).to_return(body: '<html>502</html>')

    assert_nothing_raised { invitation.delete_expense }

    assert_nil invitation.reload.deleted_at
    event = ProjectAllocationEvent.where(invitation: invitation, event_type: 'expense_deleted').last
    assert_equal 'error', event.status
    assert_equal 'JSON::ParserError', event.metadata['error_class']
  end
end
