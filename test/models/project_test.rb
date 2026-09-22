require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test 'package funding links tolerate absent metadata and preserve supported funding formats' do
    project = build(:project, packages: [
      { 'metadata' => nil },
      {},
      { 'metadata' => {} },
      { 'metadata' => { 'funding' => nil } },
      { 'metadata' => { 'funding' => 'https://opencollective.com/example' } },
      { 'metadata' => { 'funding' => { 'url' => 'https://patreon.com/example' } } },
      { 'metadata' => { 'funding' => ['https://opencollective.com/example', { 'url' => 'https://ko-fi.com/example' }] } }
    ])

    assert_equal ['https://opencollective.com/example', 'https://patreon.com/example', 'https://ko-fi.com/example'], project.package_funding_links
  end

  test 'total allocated uses a database aggregate' do
    project = create(:project)
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 100)
    create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 250)

    queries = record_select_queries do
      assert_equal 350, project.total_allocated
    end

    assert_equal 1, queries.length
    assert_includes queries.first, 'SUM("project_allocations"."amount_cents")'
  end
end
