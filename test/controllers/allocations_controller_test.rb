require "test_helper"

class AllocationsControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')
    allocation = Allocation.create!(fund_id: fund.id, year: Time.zone.now.year, month: Time.zone.now.month, total_cents: 1000_00, funded_projects_count: 0)
    get fund_allocation_url(fund, allocation)
    assert_response :success
  end

  test "show renders projects without a funding source when multiple transactions match the amount" do
    fund = create(:fund, slug: 'rust', registry_name: 'cargo')
    allocation = create(:allocation, fund: fund, year: 2026, month: 11, created_at: Time.zone.local(2026, 11, 1))
    project = create(:project, name: 'Rust project', funding_source: nil)
    create(:project_allocation, fund: fund, allocation: allocation, project: project, funding_source: nil, amount_cents: 5000)
    create(:transaction, fund: fund, amount: -50, transaction_type: 'DEBIT', transaction_kind: 'EXPENSE', account: 'first-recipient')
    create(:transaction, fund: fund, amount: -50, transaction_type: 'DEBIT', transaction_kind: 'EXPENSE', account: 'second-recipient')

    get fund_allocation_url(fund, allocation)

    assert_response :success
    assert_select 'tbody a', text: project.name
    assert_select 'tbody p', text: /Contacting Maintainer/
    assert_select 'tbody p', text: /Funding: Paid/, count: 0
  end
end
