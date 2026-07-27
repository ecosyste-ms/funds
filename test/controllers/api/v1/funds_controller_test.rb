require "test_helper"

class Api::V1::FundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund = Fund.create!(
      name: "Django",
      description: "Django is a web application framework for Python.",
      slug: "django",
      registry_name: "pypi",
    )

    @project1 = Project.create!(
      name: "Django",
      url: "https://github.com/django/django",
      licenses: ["bsd"],
      registry_names: ["pypi"],
      repository: { "archived" => false },
      funding_rejected: false,
      total_downloads: 542_000_000,
      total_dependent_repos: 604_000,
      total_dependent_packages: 8_240,
    )

    @project2 = Project.create!(
      name: "Wagtail",
      url: "https://github.com/wagtail/wagtail",
      licenses: ["bsd"],
      registry_names: ["pypi"],
      repository: { "archived" => false },
      funding_rejected: false,
      total_downloads: 1_000_000,
      total_dependent_repos: 100,
      total_dependent_packages: 50,
    )

    @allocation = Allocation.create!(
      fund: @fund,
      year: Time.zone.now.year,
      month: Time.zone.now.month,
      total_cents: 17_736_00,
      funded_projects_count: 2,
    )

    ProjectAllocation.create!(
      fund: @fund,
      allocation: @allocation,
      project: @project1,
      paid_at: Time.zone.now,
    )

    ProjectAllocation.create!(
      fund: @fund,
      allocation: @allocation,
      project: @project2,
      paid_at: Time.zone.now,
    )

    Transaction.create!(
      fund: @fund,
      legacy_id: "1",
      uuid: SecureRandom.uuid,
      amount: 16_875.00,
      net_amount: 16_875.00,
      transaction_type: "CREDIT",
      transaction_kind: "DONATION",
      currency: "USD",
      account: "sentry",
      account_name: "Sentry",
      created_at: Time.zone.now,
    )

    Transaction.create!(
      fund: @fund,
      legacy_id: "2",
      uuid: SecureRandom.uuid,
      amount: 650.00,
      net_amount: 650.00,
      transaction_type: "CREDIT",
      transaction_kind: "DONATION",
      currency: "USD",
      account: "thibaudcolas",
      account_name: "Thibaud Colas",
      created_at: Time.zone.now,
    )

    Transaction.create!(
      fund: @fund,
      legacy_id: "3",
      uuid: SecureRandom.uuid,
      amount: 51.00,
      net_amount: 51.00,
      transaction_type: "CREDIT",
      transaction_kind: "DONATION",
      currency: "USD",
      account: "chris-adams",
      account_name: "Chris Adams",
      account_image_url: nil,
      created_at: Time.zone.now,
    )

    @fund.update_stats
  end

  test "search returns matching funded packages" do
    get search_api_v1_funds_path, params: { query: "django" }
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("funds")
    assert_equal 1, json["funds"].length

    fund = json["funds"].first
    assert_equal "Django", fund["name"]
    assert_equal "Django is a web application framework for Python.", fund["description"]
    assert fund["url"].end_with?("/funds/django")
    assert_equal 3, fund["total_donors"]
  end

  test "search without query param returns bad request" do
    get search_api_v1_funds_path
    assert_response :bad_request
    assert_empty response.body
  end

  test "search with query param exceeding 100 characters returns bad request" do
    get search_api_v1_funds_path, params: { query: "a" * 101 }
    assert_response :bad_request
    assert_empty response.body
  end

  test "search with invalid page param returns bad request" do
    get search_api_v1_funds_path, params: { query: "django", page: -1 }
    assert_response :bad_request
    assert_empty response.body
  end

  test "search with no results for query returns empty funds list" do
    get search_api_v1_funds_path, params: { query: "does-not-exist" }
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("funds")
    assert_equal 0, json["funds"].length
  end

  test "search handles hostile query strings" do
    get search_api_v1_funds_path, params: { query: "') THEN 0 ELSE (SELECT 1) END --" }
    assert_response :success
    assert_empty assigns(:funds)
  end

  test "show returns fund information" do
    get api_v1_fund_path(@fund.slug)
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal 2, json["funded_projects_count"]
    assert_equal 2, json["projects_count"]
    assert_equal 3, json["total_donors"]
    assert_equal 543_000_000, json["project_downloads"]
    assert_equal 604_100, json["project_dependent_repos"]
    assert_equal 8_290, json["project_dependent_packages"]
    assert_equal 17_576.00, json["total_donation_amount"]["value"]
    assert_equal "USD", json["total_donation_amount"]["currency"]
    assert json.key?("completed_allocations_count")
    assert json.key?("completed_allocations_total")

    assert_kind_of Array, json["top_3_funders"]
    sentry = json["top_3_funders"].find { |f| f["funder_name"] == "Sentry" }
    thibaud = json["top_3_funders"].find { |f| f["funder_name"] == "Thibaud Colas" }
    chris = json["top_3_funders"].find { |f| f["funder_name"] == "Chris Adams" }
    assert_equal 16_875.00, sentry["funder_amount"]["value"]
    assert_equal "USD", sentry["funder_amount"]["currency"]
    assert_equal "https://opencollective.com/sentry", sentry["funder_link"]
    assert_equal 650.00, thibaud["funder_amount"]["value"]
    assert_equal "USD", thibaud["funder_amount"]["currency"]
    assert_equal "https://opencollective.com/thibaudcolas", thibaud["funder_link"]
    assert_equal 51.00, chris["funder_amount"]["value"]
    assert_equal "USD", chris["funder_amount"]["currency"]
    assert_equal "https://opencollective.com/chris-adams", chris["funder_link"]
  end

  test "show returns 400 for empty slug" do
    get api_v1_fund_path("   ")
    assert_response :bad_request
    assert_empty response.body
  end

  test "show returns 400 for slug exceeding 100 characters in length" do
    get api_v1_fund_path("a" * 101)
    assert_response :bad_request
    assert_empty response.body
  end

  test "show handles hostile query strings" do
    get api_v1_fund_path("') THEN 0 ELSE (SELECT 1) END --")
    assert_response :not_found
    assert_empty response.body
  end

  test "show returns 404 for unknown fund" do
    get api_v1_fund_path("missing-fund")
    assert_response :not_found
    assert_empty response.body
  end
end
