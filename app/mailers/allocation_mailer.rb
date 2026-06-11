class AllocationMailer < ApplicationMailer
  def github_sponsors_csv(recipient)
    @url = "https://funds.ecosyste.ms/admin/allocations/github_sponsors/#{Date.today.iso8601}.csv"
    mail(to: recipient, subject: 'Ecosyste.ms Funds GitHub Sponsors Bulk CSV Export')
  end
end