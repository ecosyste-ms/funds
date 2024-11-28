class MaintainerMailer < ApplicationMailer
  def invitation_email(maintainer_email, package, funders, amount, invite_url, decline_deadline)
    @project = package
    @funders = funders
    @amount = amount
    @invite_url = invite_url
    @decline_deadline = decline_deadline

    mail(to: maintainer_email, subject: "Thank you for your work maintaining #{@project}")
  end
end
