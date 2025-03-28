require "test_helper"

class FundTest < ActiveSupport::TestCase
  test 'possible_projects' do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')

    project1 = Project.create!(url: 'https://github.com/base62/base62.js', licenses: ['mit'], registry_names: ['npm'], repository: { 'archived' => false }, total_dependent_repos: 1)
    project2 = Project.create!(url: 'https://github.com/base62/archived', registry_names: ['npm'], repository: { 'archived' => true }, total_dependent_repos: 1)
    project2 = Project.create!(url: 'https://github.com/base62/nolicense', registry_names: ['npm'], repository: { 'archived' => false }, total_dependent_repos: 1)

    assert_equal 3, fund.possible_projects.count
  end
end
