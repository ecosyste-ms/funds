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

  test "should get show with no allocation" do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')
    get fund_url(fund)
    assert_response :success
  end

  test "should get search results" do
    fund1 = Fund.create!(name: 'Test Fund 1', slug: 'test1', registry_name: 'npm')
    fund2 = Fund.create!(name: 'Another Fund', slug: 'test2', registry_name: 'rubygems')
  
    get search_funds_url, params: { query: 'Test' }
    assert_response :success
  
    assert_not_nil assigns(:funds), "@funds should be set"
    assert_includes assigns(:funds), fund1, "Expected fund1 to be in @funds"
    assert_not_includes assigns(:funds), fund2, "Expected fund2 to NOT be in @funds"
  end
end
