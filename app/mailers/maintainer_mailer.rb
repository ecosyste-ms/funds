class MaintainerMailer < ApplicationMailer
  def invitation_email(maintainer_email, package, funders, amount, invite_token, decline_deadline, fund)
    @project = package
    @funders = funders
    @fund = fund
    @amount = amount
    @invite_token = invite_token
    @decline_deadline = decline_deadline

    mail(to: maintainer_email, subject: "Thank you for your work maintaining #{@project}")
  end

  def expense_email(invitation, maintainer_email, package, funders, amount, invite_token, decline_deadline, fund)
    @invitation = invitation
    @project = package
    @funders = funders
    @fund = fund
    @amount = amount
    @invite_token = invite_token
    @decline_deadline = decline_deadline

    mail(to: maintainer_email, subject: "Payment details for your work maintaining #{@project}")
  end
end
