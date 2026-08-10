require "test_helper"

class FundTest < ActiveSupport::TestCase
  test 'possible_projects' do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')

    project1 = Project.create!(url: 'https://github.com/base62/base62.js', licenses: ['mit'], registry_names: ['npm'], repository: { 'archived' => false }, total_dependent_repos: 1)
    project2 = Project.create!(url: 'https://github.com/base62/archived', registry_names: ['npm'], repository: { 'archived' => true }, total_dependent_repos: 1)
    project2 = Project.create!(url: 'https://github.com/base62/nolicense', registry_names: ['npm'], repository: { 'archived' => false }, total_dependent_repos: 1)

    assert_equal 3, fund.possible_projects.count
  end

  test 'possible project totals are calculated in one query' do
    fund = create(:fund, primary_topic: nil, registry_name: 'npm')
    create(:project, registry_names: ['npm'], total_downloads: 10, total_dependent_repos: 20, total_dependent_packages: 30)
    create(:project, registry_names: ['npm'], total_downloads: 1, total_dependent_repos: 2, total_dependent_packages: 3)
    create(:project, registry_names: ['npm'], funding_rejected: true, total_downloads: 100, total_dependent_repos: 100, total_dependent_packages: 100)
    create(:project, registry_names: ['other'], total_downloads: 100, total_dependent_repos: 100, total_dependent_packages: 100)

    queries = record_select_queries do
      assert_equal 11, fund.possible_project_downloads
      assert_equal 22, fund.possible_project_dependent_repos
      assert_equal 33, fund.possible_project_dependent_packages
      assert_equal 11, fund.possible_project_downloads
    end

    aggregate_queries = queries.select { |sql| sql.include?('SUM("projects"."total_downloads")') }
    assert_equal 1, aggregate_queries.length
  end

  test 'top funded projects are ranked without loading project allocations' do
    fund = create(:fund)
    other_fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    other_allocation = create(:allocation, fund: other_fund)
    first_project = create(:project)
    second_project = create(:project)
    unpaid_project = create(:project)
    rejected_project = create(:project, funding_rejected: true)

    create(:project_allocation, fund: fund, allocation: allocation, project: first_project, amount_cents: 100, paid_at: Time.current)
    create(:project_allocation, fund: other_fund, allocation: other_allocation, project: first_project, amount_cents: 900, paid_at: Time.current)
    create(:project_allocation, fund: fund, allocation: allocation, project: second_project, amount_cents: 500, paid_at: Time.current)
    create(:project_allocation, fund: fund, allocation: allocation, project: unpaid_project, amount_cents: 2000, paid_at: nil)
    create(:project_allocation, fund: fund, allocation: allocation, project: rejected_project, amount_cents: 3000, paid_at: Time.current)

    projects = nil
    queries = record_select_queries do
      projects = fund.top_funded_projects.to_a
      projects.map(&:total_allocated)
    end

    assert_equal [first_project, second_project], projects
    assert_equal [1000, 500], projects.map(&:total_allocated)
    assert_equal 1, queries.length
  end

  test 'allocations with totals loads every allocation summary in one query' do
    fund = create(:fund)
    january = create(:allocation, fund: fund, year: 2026, month: 1, funded_projects_count: 2)
    february = create(:allocation, fund: fund, year: 2026, month: 2, funded_projects_count: 1)
    project = create(:project)

    create(:project_allocation, fund: fund, allocation: january, project: project, amount_cents: 100)
    create(:project_allocation, fund: fund, allocation: january, project: project, amount_cents: 250)
    create(:project_allocation, fund: fund, allocation: february, project: project, amount_cents: 500)

    allocations = nil
    queries = record_select_queries do
      allocations = fund.allocations_with_totals.to_a
      allocations.map { |allocation| [allocation.total_allocated_cents, allocation.projects_count] }
    end

    assert_equal [february, january], allocations
    assert_equal [500, 350], allocations.map(&:total_allocated_cents)
    assert_equal [1, 2], allocations.map(&:projects_count)
    assert_equal 1, queries.length
  end

  test 'registry names has a GIN index' do
    index = ActiveRecord::Base.connection.indexes(:projects).find { |candidate| candidate.columns == ['registry_names'] }

    assert_not_nil index
    assert_equal :gin, index.using
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

  test 'search treats query as a literal in the order clause' do
    create(:fund, name: "d'Artagnan tools")
    exact = create(:fund, name: "d'Artagnan")

    results = Fund.search("d'Artagnan")

    assert_equal exact, results.first
    assert_equal 2, results.length
  end

  test 'search escapes LIKE wildcards in query' do
    create(:fund, name: 'Underscore')
    match = create(:fund, name: '100% Open')

    assert_equal [match], Fund.search('100%').to_a
    assert_empty Fund.search('Under_core')
  end

  test 'stat readers use stored columns without querying' do
    fund = create(:fund, total_donation_amount_cents: 12345, total_donors_count: 7, completed_allocations_total_cents: 6789)

    assert_equal 123.45, fund.total_donation_amount
    assert_equal 7, fund.total_donors
    assert_equal 67.89, fund.completed_allocations_total
  end
end
