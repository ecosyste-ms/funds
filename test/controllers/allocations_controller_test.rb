require "test_helper"

class AllocationsControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')
    allocation = Allocation.create!(fund_id: fund.id, year: Time.zone.now.year, month: Time.zone.now.month, total_cents: 1000_00, funded_projects_count: 0)
    get fund_allocation_url(fund, allocation)
    assert_response :success
  end
end
