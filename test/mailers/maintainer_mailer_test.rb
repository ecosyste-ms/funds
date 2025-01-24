require "test_helper"

class MaintainerMailerTest < ActionMailer::TestCase
  test "invitation_email" do
    # Set up email parameters
    maintainer_email = "maintainer@example.com"
    package = "example-project"
    funders = "Sentry"
    amount = "$500.00"
    invite_token = "123456"
    decline_deadline = (Time.now + 14.days).strftime("%B %d, %Y")
    fund = create(:fund)

    # Send the email
    email = MaintainerMailer.invitation_email(
      maintainer_email,
      package,
      funders,
      amount,
      invite_token,
      decline_deadline,
      fund
    )

    # Assert email properties
    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["maintainer@example.com"], email.to
    assert_equal ["hello@oscollective.org"], email.from
    assert_equal "Thank you for your work maintaining #{package}", email.subject

    # Assert email body contains expected content
    assert_includes email.html_part.body.to_s, "Sentry"
    assert_includes email.html_part.body.to_s, invite_token
    assert_includes email.html_part.body.to_s, decline_deadline
    assert_includes email.html_part.body.to_s, 'src="https://funds.ecosyste.ms'

    assert_includes email.text_part.body.to_s, "Sentry"
    assert_includes email.text_part.body.to_s, invite_token
    assert_includes email.text_part.body.to_s, decline_deadline

    assert_includes email.html_part.body.to_s, "font-family: system-ui"
    assert_includes email.html_part.body.to_s, "color: #1D1D28"
  end

  test "expense_email" do
    data = {"draftKey" => "123"}
    project_allocation = create(:project_allocation)
    invitation = Invitation.create!(email: "maintainer@example.com", project_allocation: project_allocation, data: data, member_invitation_id: 123)
    maintainer_email = "maintainer@example.com"
    package = "example-project"
    funders = "Sentry"
    amount = "$500.00"
    invite_token = "123456"
    decline_deadline = (Time.now + 14.days).strftime("%B %d, %Y")
    fund = create(:fund)

    # Send the email
    email = MaintainerMailer.expense_email(
      invitation,
      maintainer_email,
      package,
      funders,
      amount,
      invite_token,
      decline_deadline,
      fund
    )

    # Assert email properties
    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["maintainer@example.com"], email.to
    assert_equal ["hello@oscollective.org"], email.from
    assert_equal "Payment details for your work maintaining #{package}", email.subject

    # Assert email body contains expected content
    assert_includes email.html_part.body.to_s, "Sentry"
    assert_includes email.html_part.body.to_s, invite_token
    assert_includes email.html_part.body.to_s, decline_deadline
    assert_includes email.html_part.body.to_s, 'src="https://funds.ecosyste.ms'

    assert_includes email.text_part.body.to_s, "Sentry"
    assert_includes email.text_part.body.to_s, invite_token
    assert_includes email.text_part.body.to_s, decline_deadline

    assert_includes email.html_part.body.to_s, "font-family: system-ui"
    assert_includes email.html_part.body.to_s, "color: #1D1D28"
  end
end