require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test "should get show for project without allocations" do
    project = create(:project)
    get project_url(project)
    assert_response :success
    assert_select "h1", text: /#{Regexp.escape(project.to_s)}/
    assert_select ".alert-info", text: /has not received any funding allocations/
  end

  test "should get show for project with allocations" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project)
    project_allocation = create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 5000)

    get project_url(project)
    assert_response :success
    assert_select "h1", text: /#{Regexp.escape(project.to_s)}/
    assert_select ".card-header", text: /#{Regexp.escape(fund.name)}/
    assert_select "td", text: "$50.00"
  end

  test "should get show for project with allocations from multiple funds" do
    fund1 = create(:fund)
    fund2 = create(:fund)
    allocation1 = create(:allocation, fund: fund1)
    allocation2 = create(:allocation, fund: fund2)
    project = create(:project)
    create(:project_allocation, project: project, fund: fund1, allocation: allocation1, amount_cents: 5000)
    create(:project_allocation, project: project, fund: fund2, allocation: allocation2, amount_cents: 10000)

    get project_url(project)
    assert_response :success
    assert_select ".card-header", count: 2
    assert_select ".card-header", text: /#{Regexp.escape(fund1.name)}/
    assert_select ".card-header", text: /#{Regexp.escape(fund2.name)}/
  end

  test "should show paid status for paid allocation" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project)
    project_allocation = create(:project_allocation, project: project, fund: fund, allocation: allocation, paid_at: Time.current)

    get project_url(project)
    assert_response :success
    assert_select ".badge.bg-success", text: "Paid"
  end

  test "should show rejected status for rejected funding" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project, funding_rejected: true)
    project_allocation = create(:project_allocation, project: project, fund: fund, allocation: allocation)

    get project_url(project)
    assert_response :success
    assert_select ".badge.bg-danger", text: "Rejected"
  end

  test "should show invitation pending status" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project)
    project_allocation = create(:project_allocation, project: project, fund: fund, allocation: allocation, funding_source: nil)
    create(:invitation, project_allocation: project_allocation)

    get project_url(project)
    assert_response :success
    assert_select ".badge.bg-warning", text: "Invitation Pending"
  end

  test "should show awaiting payment status for accepted invitation" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project)
    project_allocation = create(:project_allocation, project: project, fund: fund, allocation: allocation, funding_source: nil)
    create(:invitation, project_allocation: project_allocation, accepted_at: Time.current)

    get project_url(project)
    assert_response :success
    assert_select ".badge.bg-info", text: "Awaiting Payment"
  end

  test "should display total allocated amount" do
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project)
    create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 5000)
    create(:project_allocation, project: project, fund: fund, allocation: create(:allocation, fund: fund), amount_cents: 3000)

    get project_url(project)
    assert_response :success
    assert_select ".card.bg-light", text: /Total Allocated.*\$80\.00/m
  end

  test "should display total allocated amount for specific fund" do
    test_fund = create(:fund, name: "Test Fund", slug: "test-fund-cents")
    test_fund_2 = create(:fund, name: "Test Fund 2", slug: "test-fund-cents-2")
    test_allocation = create(
      :allocation,
      fund: test_fund,
      year: Time.zone.now.year,
      month: Time.zone.now.month,
      total_cents: 123_45,
      funded_projects_count: 1,
    )
    test_allocation_2 = create(
      :allocation,
      fund: test_fund_2,
      year: Time.zone.now.year,
      month: Time.zone.now.month,
      total_cents: 678_90,
      funded_projects_count: 1,
    )
    project = create(
      :project,
      registry_names: ["pypi"],
      keywords: ["python"],
      funding_rejected: false,
      total_downloads: 1_000_000,
      total_dependent_repos: 100,
      total_dependent_packages: 50,
    )
    create(
      :project_allocation,
      fund: test_fund,
      allocation: test_allocation,
      project: project,
      paid_at: Time.zone.now,
      amount_cents: 123_45,
    )
    create(
      :project_allocation,
      fund: test_fund_2,
      allocation: test_allocation_2,
      project: project,
      paid_at: Time.zone.now,
      amount_cents: 678_90,
    )
    test_fund.update_stats
    test_fund_2.update_stats

    # project funding from test 1
    get fund_projects_path(test_fund)
    assert_response :success
    assert_select "tr" do
      assert_select "td:nth-child(2) a", text: "$123.45"
    end

    # project funding from test 2
    get fund_projects_path(test_fund_2)
    assert_response :success
    assert_select "tr" do
      assert_select "td:nth-child(2) a", text: "$678.90"
    end
  end
end
