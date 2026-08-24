require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  require "test_helper"

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