require "test_helper"

class FundTest < ActiveSupport::TestCase
  test 'possible_projects' do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')

    project1 = Project.create!(url: 'https://github.com/base62/base62.js', licenses: ['mit'], registry_names: ['npm'], repository: { 'archived' => false }, total_dependent_repos: 1)
    project2 = Project.create!(url: 'https://github.com/base62/archived', registry_names: ['npm'], repository: { 'archived' => true }, total_dependent_repos: 1)
    project2 = Project.create!(url: 'https://github.com/base62/nolicense', registry_names: ['npm'], repository: { 'archived' => false }, total_dependent_repos: 1)

    assert_equal 3, fund.possible_projects.count
  end

  test 'update_stats stores donation totals and donor count from transactions' do
    fund = create(:fund)
    Transaction.create!(fund: fund, uuid: SecureRandom.uuid, transaction_type: 'CREDIT', account: 'alice', amount: 100.0, net_amount: 95.0)
    Transaction.create!(fund: fund, uuid: SecureRandom.uuid, transaction_type: 'CREDIT', account: 'alice', amount: 50.0, net_amount: 47.5)
    Transaction.create!(fund: fund, uuid: SecureRandom.uuid, transaction_type: 'CREDIT', account: 'bob', amount: 25.0, net_amount: 23.75)
    Transaction.create!(fund: fund, uuid: SecureRandom.uuid, transaction_type: 'DEBIT', account: 'payee', amount: -10.0, net_amount: -10.0)

    fund.update_stats

    assert_equal 17500, fund.total_donation_amount_cents
    assert_equal 175.0, fund.total_donation_amount
    assert_equal 2, fund.total_donors_count
    assert_equal 2, fund.total_donors
    assert_in_delta 156.25, fund.balance, 0.001
  end

  test 'update_stats stores completed allocations total from successful project allocations' do
    fund = create(:fund)
    project = create(:project, funding_rejected: false)
    completed = create(:allocation, fund: fund, completed_at: 1.day.ago)
    pending = create(:allocation, fund: fund, completed_at: nil)

    paid = create(:project_allocation, fund: fund, allocation: completed, project: project, amount_cents: 4000)
    create(:invitation, project_allocation: paid, data: { 'status' => 'PAID' })

    rejected = create(:project_allocation, fund: fund, allocation: completed, project: project, amount_cents: 1000)
    create(:invitation, project_allocation: rejected, data: { 'status' => 'REJECTED' })

    not_yet = create(:project_allocation, fund: fund, allocation: pending, project: project, amount_cents: 9999)
    create(:invitation, project_allocation: not_yet, data: { 'status' => 'PAID' })

    fund.update_stats

    assert_equal 4000, fund.completed_allocations_total_cents
    assert_equal 40.0, fund.completed_allocations_total
  end

  test 'stat readers use stored columns without querying' do
    fund = create(:fund, total_donation_amount_cents: 12345, total_donors_count: 7, completed_allocations_total_cents: 6789)

    assert_equal 123.45, fund.total_donation_amount
    assert_equal 7, fund.total_donors
    assert_equal 67.89, fund.completed_allocations_total
  end
end
