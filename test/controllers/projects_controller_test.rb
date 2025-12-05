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
end
