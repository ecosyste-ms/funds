# Preview all emails at http://localhost:3000/rails/mailers/allocation_mailer
class AllocationMailerPreview < ActionMailer::Preview
  def github_sponsors_csv
    AllocationMailer.github_sponsors_csv("test@example.com")
  end
end
