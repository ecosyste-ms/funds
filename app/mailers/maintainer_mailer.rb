class MaintainerMailer < ApplicationMailer
  def invitation_email(maintainer_email, package, funders, amount, invite_token, decline_deadline)
    @project = package
    @funders = funders
    @amount = amount
    @invite_token = invite_token
    @decline_deadline = decline_deadline

    mail(to: maintainer_email, subject: "Thank you for your work maintaining #{@project}")
  end
end
