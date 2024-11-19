require "test_helper"

class FundsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get funds_url
    assert_response :success
  end

  test "should get show" do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')
    Allocation.create!(fund: fund, total_cents: 10_000_00)
    get fund_url(fund)
    assert_response :success
  end
end
