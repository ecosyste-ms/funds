require "test_helper"

class AllocationMailerTest < ActionMailer::TestCase
  test "github_sponsors_csv email is sent with correct content" do
    email = AllocationMailer.github_sponsors_csv("test@example.com")

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["test@example.com"], email.to
    assert_equal "Ecosyste.ms Funds GitHub Sponsors Bulk CSV Export", email.subject
    assert_match "https://funds.ecosyste.ms/admin/allocations/github_sponsors.csv", email.body.to_s
  end
end
