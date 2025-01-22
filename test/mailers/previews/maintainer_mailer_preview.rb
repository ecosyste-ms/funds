# Preview all emails at http://localhost:3000/rails/mailers/maintainer_mailer
class MaintainerMailerPreview < ActionMailer::Preview
  def invitation_email
    MaintainerMailer.invitation_email(
      "maintainer@example.com",
      "example-project",
      "Sentry",
      "$500.00",
      "123456",
      (Time.now + 14.days).strftime("%B %d, %Y"),
      Fund.first
    )
  end

  def expense_email
    data = {"draftKey" => "123"}
    invitation = Invitation.create!(email: "maintainer@example.com", project_allocation: ProjectAllocation.first, data: data, member_invitation_id: 123)
    MaintainerMailer.expense_email(
      invitation,
      "maintainer@example.com",
      "example-project",
      "Sentry",
      "$500.00",
      "123456",
      (Time.now + 14.days).strftime("%B %d, %Y"),
      Fund.first
    )
  end
end