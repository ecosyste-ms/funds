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
end