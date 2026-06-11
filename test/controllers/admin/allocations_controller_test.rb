require "test_helper"

class Admin::AllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund = create(:fund)
    @funding_source = create(:funding_source, url: 'https://github.com/sponsors/dtolnay', platform: 'github.com', github_sponsors: {})
    @allocation = create(:allocation, fund: @fund, created_at: Time.utc(2025, 5, 1))
    @project = create(:project)
    create(:project_allocation, allocation: @allocation, project: @project, fund: @fund, funding_source: @funding_source, amount_cents: 5000)
  end

  test "github_sponsors without date redirects to today's dated export" do
    get github_sponsors_admin_allocations_url(format: :csv)
    assert_redirected_to github_sponsors_dated_admin_allocations_url(date: Date.today.iso8601, format: :csv)
  end

  test "dated github_sponsors includes allocations not completed on that date" do
    get github_sponsors_dated_admin_allocations_url(date: '2025-05-15', format: :csv)
    assert_response :success
    assert_match 'dtolnay', response.body
    assert_match 'github_sponsors-2025-05-15.csv', response.headers['Content-Disposition']
  end

  test "dated github_sponsors excludes allocations completed before that date" do
    @allocation.update!(completed_at: Time.utc(2025, 5, 28))
    get github_sponsors_dated_admin_allocations_url(date: '2025-06-15', format: :csv)
    assert_response :success
    refute_match 'dtolnay', response.body
  end

  test "dated github_sponsors excludes allocations created after that date" do
    get github_sponsors_dated_admin_allocations_url(date: '2025-04-15', format: :csv)
    assert_response :success
    refute_match 'dtolnay', response.body
  end

  test "dated github_sponsors returns 404 for invalid date" do
    get github_sponsors_dated_admin_allocations_url(date: '2025-99-99', format: :csv)
    assert_response :not_found
  end
end
