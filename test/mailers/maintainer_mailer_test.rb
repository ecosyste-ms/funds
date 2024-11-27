require "test_helper"

class MaintainerMailerTest < ActionMailer::TestCase
  test "invitation_email" do
    # Set up email parameters
    maintainer_email = "maintainer@example.com"
    package = "example-package"
    funders = "Open Source Collective"
    amount = "$500"
    invite_url = "https://example.com/invite"
    decline_deadline = (Time.now + 14.days).strftime("%B %d, %Y")

    # Send the email
    email = MaintainerMailer.invitation_email(
      maintainer_email,
      package,
      funders,
      amount,
      invite_url,
      decline_deadline
    )

    # Assert email properties
    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["maintainer@example.com"], email.to
    assert_equal ["from@example.com"], email.from # Update if you customized the sender
    assert_equal "Thank you for your work maintaining #{package}", email.subject

    # Assert email body contains expected content
    assert_includes email.html_part.body.to_s, "Open Source Collective"
    assert_includes email.html_part.body.to_s, invite_url
    assert_includes email.html_part.body.to_s, decline_deadline

    assert_includes email.text_part.body.to_s, "Open Source Collective"
    assert_includes email.text_part.body.to_s, invite_url
    assert_includes email.text_part.body.to_s, decline_deadline

    assert_includes email.html_part.body.to_s, "font-family: system-ui"
    assert_includes email.html_part.body.to_s, "color: #1D1D28"
  end
end