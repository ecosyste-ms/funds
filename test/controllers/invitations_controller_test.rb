require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "should get show with valid token" do
    invitation = create(:invitation)
    get invitation_url(token: invitation.token)
    assert_response :success
  end

  test "should return not found with invalid token" do
    get invitation_url(token: 'invalid_token')
    assert_response :not_found
  end

  test "accept should work without CSRF token" do
    invitation = create(:invitation)

    # Simulate a POST request without a CSRF token (like from an email client)
    post accept_invitation_url(token: invitation.token), headers: { 'HTTP_ORIGIN' => 'null' }

    assert_response :redirect
    assert_redirected_to invitation_path(token: invitation.token)

    invitation.reload
    assert invitation.accepted?
  end

  test "reject should work without CSRF token" do
    invitation = create(:invitation)

    # Simulate a POST request without a CSRF token (like from an email client)
    post reject_invitation_url(token: invitation.token), headers: { 'HTTP_ORIGIN' => 'null' }

    assert_response :redirect
    assert_redirected_to invitation_path(token: invitation.token)

    invitation.reload
    assert invitation.rejected?
  end

  test "accept should return not found with invalid token" do
    post accept_invitation_url(token: 'invalid_token')
    assert_response :not_found
  end

  test "reject should return not found with invalid token" do
    post reject_invitation_url(token: 'invalid_token')
    assert_response :not_found
  end
end
