require 'test_helper'

class ProjectFundingTotalsTest < ActionDispatch::IntegrationTest
  test 'project detail and fund listings agree on the reported DRF allocations' do
    fund = create(:fund)
    project = create(:project)
    amounts = [284466, 53300, 23269, 23694, 24119, 24544, 24969, 20109, 16641, 13868]
    amounts.each_with_index do |amount, index|
      allocation = create(:allocation, fund: fund, year: 2025, month: index + 1)
      pa = create(:project_allocation, fund: fund, allocation: allocation, project: project,
        amount_cents: amount, paid_at: [0, 1, 9].include?(index) ? Time.current : nil)
      next unless pa.paid?

      status = index == 9 ? 'APPROVED' : 'PAID'
      create(:invitation, project_allocation: pa, member_invitation_id: "expense-#{index}",
        status: status, data: { 'status' => index == 9 ? 'PENDING' : status })
    end

    get project_path(project)
    assert_response :success
    assert_select 'tbody tr', count: 10
    assert_select 'tfoot th', text: '$3,516.34'
    assert_select '.card.bg-light', text: /Total Funded:.*\$3,516\.34/m

    get fund_projects_path(fund)
    assert_response :success
    assert_select 'td:nth-child(2) a', text: '$3,516.34'

    get api_v1_fund_projects_path(fund_slug: fund.slug)
    assert_response :success
    assert_equal 3516.34, response.parsed_body['projects'].first['allocated_amount']['value']
  end

  test 'only funded amounts contribute to detail subtotals listings and rankings' do
    fund = create(:fund)
    other_fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    project = create(:project)
    approved = create(:project_allocation, fund: fund, allocation: allocation, project: project, amount_cents: 1000)
    create(:invitation, project_allocation: approved, status: 'APPROVED', data: { 'status' => 'PENDING' })
    create(:project_allocation, fund: other_fund, allocation: create(:allocation, fund: other_fund),
      project: project, amount_cents: 2500, paid_at: Time.current)
    pending = create(:project_allocation, fund: fund, allocation: allocation, project: project,
      amount_cents: 9000, paid_at: Time.current)
    create(:invitation, project_allocation: pending, status: 'PENDING')
    deleted_project = create(:project)
    deleted = create(:project_allocation, fund: fund, allocation: allocation, project: deleted_project,
      amount_cents: 8000, paid_at: Time.current)
    create(:invitation, project_allocation: deleted)
    create(:invitation, project_allocation: deleted, member_invitation_id: 'deleted-expense', status: 'PAID', deleted_at: Time.current)

    get project_path(project)
    assert_response :success
    assert_select 'tfoot th', text: '$10.00'
    assert_select 'tfoot th', text: '$25.00'
    assert_select '.card.bg-light', text: /Total Funded:.*\$35\.00/m

    get fund_projects_path(fund)
    assert_response :success
    assert_select 'td:nth-child(2) a', text: '$10.00'
    assert_select "a[href='#{project_path(deleted_project)}']", count: 0

    get api_v1_fund_projects_path(fund_slug: fund.slug)
    assert_response :success
    assert_equal 1, response.parsed_body['funded_projects_count']
    assert_equal [10.0], response.parsed_body['projects'].map { |row| row['allocated_amount']['value'] }

    get fund_path(fund)
    assert_response :success
    assert_select 'td', text: '$35.00'
    assert_equal [3500], fund.top_funded_projects.map(&:total_funded)
    assert_equal 3500, project.total_funded
  end
end
