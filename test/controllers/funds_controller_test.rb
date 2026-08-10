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

  test "show does not query allocation totals and project counts per allocation" do
    fund = create(:fund, primary_topic: nil, registry_name: 'npm')
    project = create(:project, registry_names: ['npm'], total_downloads: 1)
    january = create(:allocation, fund: fund, year: 2026, month: 1, funded_projects_count: 1)
    february = create(:allocation, fund: fund, year: 2026, month: 2, funded_projects_count: 1)
    create(:project_allocation, fund: fund, allocation: january, project: project, amount_cents: 100, paid_at: Time.current)
    create(:project_allocation, fund: fund, allocation: february, project: project, amount_cents: 200, paid_at: Time.current)

    queries = record_select_queries { get fund_url(fund) }

    assert_response :success
    assert_not queries.any? { |sql| sql.match?(/SELECT SUM\(.+\) FROM "project_allocations" WHERE "project_allocations"\."allocation_id"/) }
    assert_not queries.any? { |sql| sql.match?(/SELECT COUNT\(\*\) FROM "projects".+"project_allocations"\."allocation_id"/) }
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

  test "search redirects to all funds when query is blank" do
    get search_funds_url, params: { query: '' }
    assert_redirected_to all_funds_path

    get search_funds_url
    assert_redirected_to all_funds_path
  end

  test "search handles hostile query strings" do
    get search_funds_url, params: { query: "') THEN 0 ELSE (SELECT 1) END --" }
    assert_response :success
    assert_empty assigns(:funds)
  end
end
