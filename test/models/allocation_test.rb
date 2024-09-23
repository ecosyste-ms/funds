require "test_helper"

class AllocationTest < ActiveSupport::TestCase
  test 'calculate_funded_projects' do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')

    project1 = Project.create!(url: 'https://github.com/base62/base62.js', registry_names: ['npm'], repository: { 'archived' => false })
    project1.stubs(:downloads).returns(100)
    project1.stubs(:dependent_repos).returns(100)
    project1.stubs(:dependent_packages).returns(100)
    
    project2 = Project.create!(url: 'https://github.com/reduxjs/redux', registry_names: ['npm'], repository: { 'archived' => false })
    project2.stubs(:downloads).returns(100)
    project2.stubs(:dependent_repos).returns(100)
    project2.stubs(:dependent_packages).returns(100)

    project3 = Project.create!(url: 'https://github.com/expressjs/express', registry_names: ['npm'], repository: { 'archived' => false })
    project3.stubs(:downloads).returns(100)
    project3.stubs(:dependent_repos).returns(100)
    project3.stubs(:dependent_packages).returns(100)
    
    assert_equal 3, fund.possible_projects.count

    allocation = Allocation.create!(fund_id: fund.id, year: Time.zone.now.year, month: Time.zone.now.month, total_cents: 1000_00)
    allocation.calculate_funded_projects

    

    assert_equal 3, allocation.funded_projects_count
    # assert_equal 334, ProjectAllocation.where(project_id: project1.id).first.amount_cents
    # assert_equal 333, ProjectAllocation.where(project_id: project2.id).first.amount_cents
    # assert_equal 333, ProjectAllocation.where(project_id: project3.id).first.amount_cents
  end
end
