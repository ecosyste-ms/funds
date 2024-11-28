# Preview all emails at http://localhost:3000/rails/mailers/maintainer_mailer
class MaintainerMailerPreview < ActionMailer::Preview
  def invitation_email
    MaintainerMailer.invitation_email(
      "maintainer@example.com",
      "example-project",
      "Sentry",
      "$500.00",
      "https://example.com/invite",
      (Time.now + 14.days).strftime("%B %d, %Y")
    )
  end
end