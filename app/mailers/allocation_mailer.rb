class AllocationMailer < ApplicationMailer
  def github_sponsors_csv(recipient)
    @url = 'https://funds.ecosyste.ms/admin/allocations/github_sponsors.csv'
    mail(to: recipient, subject: 'Ecosyste.ms Funds GitHub Sponsors Bulk CSV Export')
  end
end