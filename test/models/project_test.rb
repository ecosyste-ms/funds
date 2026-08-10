require "test_helper"

class ProjectTest < ActiveSupport::TestCase
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
