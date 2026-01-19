require "test_helper"

class AllocationTest < ActiveSupport::TestCase
  def setup
    @fund = Fund.create!(name: 'Test Fund', slug: 'test', registry_name: 'npm')

    @project1 = Project.create!(url: 'https://github.com/base62/base62.js', licenses: ['mit'], registry_names: ['npm'], repository: { 'archived' => false })
    @project1.stubs(:downloads).returns(200)
    @project1.stubs(:dependent_repos).returns(100)
    @project1.stubs(:dependent_packages).returns(100)

    @project2 = Project.create!(url: 'https://github.com/reduxjs/redux', licenses: ['mit'], registry_names: ['npm'], repository: { 'archived' => false })
    @project2.stubs(:downloads).returns(300)
    @project2.stubs(:dependent_repos).returns(100)
    @project2.stubs(:dependent_packages).returns(100)

    @project3 = Project.create!(url: 'https://github.com/expressjs/express', licenses: ['mit'], registry_names: ['npm'], repository: { 'archived' => false })
    @project3.stubs(:downloads).returns(100)
    @project3.stubs(:dependent_repos).returns(100)
    @project3.stubs(:dependent_packages).returns(100)

    @allocation = Allocation.create!(fund_id: @fund.id, year: Time.zone.now.year, month: Time.zone.now.month, total_cents: 100_000)
  end

  test 'fetch_project_metrics returns normalized metrics' do
    metrics, maxs = @allocation.fetch_project_metrics([@project1, @project2, @project3])
    
    assert_equal 3, metrics.size
    assert metrics.first.key?(:project_id)
    assert metrics.first.key?(:downloads)
    assert metrics.first.key?(:dependent_repos)
    assert metrics.first.key?(:dependent_packages)
  end

  test 'calculate_scores computes correct scores' do
    weights = { downloads: 0.5, dependent_repos: 0.3, dependent_packages: 0.2 }
    normalized_metrics, _ = @allocation.fetch_project_metrics([@project1, @project2, @project3])
    scores, total_score = @allocation.calculate_scores(normalized_metrics, weights)

    assert_equal 3, scores.size
    assert total_score.positive?, 'Total score should be greater than zero'
    assert scores.all? { |s| s[:score] >= 0 }, 'All scores should be non-negative'
  end

  test 'allocate_funds_evenly distributes funds correctly' do
    scores = [
      { project_id: 1, score: 10 },
      { project_id: 2, score: 10 },
      { project_id: 3, score: 10 }
    ]

    allocations = @allocation.allocate_funds_evenly(scores)

    assert_equal 3, allocations.size
    assert allocations.all? { |a| a[:allocation] == 100_000 / 3 }
  end

  test 'allocate_funds_by_score distributes funds proportionally' do
    scores = [
      { project_id: 1, score: 10 },
      { project_id: 2, score: 30 },
      { project_id: 3, score: 60 }
    ]

    
    total_cents = 30000
    total_score = scores.sum { |s| s[:score] }
  
    allocations, total_allocated, leftover_funds = @allocation.allocate_funds_by_score(scores, total_score)
  
    assert allocations.any?, "Expected allocations to be assigned"
    assert_in_delta total_cents, total_allocated, 100, "Total allocated is incorrect"
  end

  test 'distribute_leftover_funds assigns remainder to first project' do
      
    scores = [
      { project_id: 1, score: 20, funding_source_id: nil },
      { project_id: 2, score: 20, funding_source_id: nil },
      { project_id: 3, score: 20, funding_source_id: nil }
    ]

    allocations = [
      { project_id: 1, allocation: 33_333 },
      { project_id: 2, allocation: 33_333 },
      { project_id: 3, allocation: 33_333 }
    ]

    @allocation.stubs(:total_cents).returns(100_000)
    @allocation.distribute_leftover_funds(allocations, scores)

    assert_equal 33_333, allocations.first[:allocation]
    assert_equal 33_333, allocations[1][:allocation]
    assert_equal 33_333, allocations[2][:allocation]
  end

  test 'save_project_allocations persists correct allocations' do
    allocations = [
      { project_id: @project1.id, allocation: 40_000, score: 0.4, funding_source_id: 1 },
      { project_id: @project2.id, allocation: 30_000, score: 0.3, funding_source_id: 1 },
      { project_id: @project3.id, allocation: 30_000, score: 0.3, funding_source_id: 1 }
    ]

    @allocation.save_project_allocations(allocations, 5000, {}, {})

    assert_equal 3, ProjectAllocation.count
    assert_equal 40_000, ProjectAllocation.find_by(project_id: @project1.id).amount_cents
  end

  test 'payout_proxy_collectives_aggregated groups allocations by funding source' do
    funding_source = FundingSource.create!(
      url: 'https://github.com/sponsors/testuser',
      platform: 'github.com',
      github_sponsors: { 'minimum_sponsorship_amount' => 100 }
    )

    project1 = Project.create!(
      url: 'https://github.com/test/project1',
      licenses: ['mit'],
      registry_names: ['npm'],
      repository: { 'archived' => false },
      funding_source: funding_source,
      owner: { 'email' => 'test@example.com' }
    )

    project2 = Project.create!(
      url: 'https://github.com/test/project2',
      licenses: ['mit'],
      registry_names: ['npm'],
      repository: { 'archived' => false },
      funding_source: funding_source,
      owner: { 'email' => 'test@example.com' }
    )

    # Each allocation is $50 (below $100 minimum), but together they're $100
    pa1 = ProjectAllocation.create!(
      allocation: @allocation,
      project: project1,
      fund: @fund,
      funding_source: funding_source,
      amount_cents: 5000,
      score: 0.5
    )

    pa2 = ProjectAllocation.create!(
      allocation: @allocation,
      project: project2,
      fund: @fund,
      funding_source: funding_source,
      amount_cents: 5000,
      score: 0.5
    )

    # Verify they're grouped together
    proxy_allocations = @allocation.project_allocations.includes(:funding_source, :project)
      .select(&:is_proxy_collective?)
      .reject(&:paid?)
      .reject(&:funding_rejected?)

    grouped = proxy_allocations.group_by(&:funding_source_id)

    assert_equal 1, grouped.keys.length
    assert_equal 2, grouped[funding_source.id].length
    assert_equal 10000, grouped[funding_source.id].sum(&:amount_cents)
  end

  test 'payout_proxy_collectives_aggregated falls back to email when aggregated total still below minimum' do
    funding_source = FundingSource.create!(
      url: 'https://github.com/sponsors/testuser',
      platform: 'github.com',
      github_sponsors: { 'minimum_sponsorship_amount' => 200 }
    )

    project1 = Project.create!(
      url: 'https://github.com/test/project1',
      licenses: ['mit'],
      registry_names: ['npm'],
      repository: { 'archived' => false },
      funding_source: funding_source,
      owner: { 'email' => 'test@example.com' }
    )

    project2 = Project.create!(
      url: 'https://github.com/test/project2',
      licenses: ['mit'],
      registry_names: ['npm'],
      repository: { 'archived' => false },
      funding_source: funding_source,
      owner: { 'email' => 'test@example.com' }
    )

    # Each allocation is $50, total is $100, but minimum is $200
    pa1 = ProjectAllocation.create!(
      allocation: @allocation,
      project: project1,
      fund: @fund,
      funding_source: funding_source,
      amount_cents: 5000,
      score: 0.5
    )

    pa2 = ProjectAllocation.create!(
      allocation: @allocation,
      project: project2,
      fund: @fund,
      funding_source: funding_source,
      amount_cents: 5000,
      score: 0.5
    )

    # Stub the OC API call for email fallback
    stub_request(:post, /opencollective/).to_return(
      status: 200,
      body: { data: { draftExpenseAndInviteUser: { id: '123', legacyId: 456, status: 'DRAFT', draftKey: 'abc' } } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    @allocation.payout_proxy_collectives_aggregated

    # Should have logged payout_skipped events with fallback message for each allocation
    pa1.reload
    pa2.reload

    event1 = pa1.events.find_by(event_type: 'payout_skipped')
    event2 = pa2.events.find_by(event_type: 'payout_skipped')

    assert_not_nil event1
    assert_not_nil event2
    assert_match(/Aggregated total below minimum/, event1.message)
    assert_equal 10000, event1.metadata['aggregated_total_cents']
    assert_equal 20000, event1.metadata['minimum_cents']
  end
end