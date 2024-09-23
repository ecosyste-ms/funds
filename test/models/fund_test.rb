require "test_helper"

class FundTest < ActiveSupport::TestCase
  test 'possible_projects' do
    fund = Fund.create!(name: 'Test Fund', slug: 'test', 'registry_name': 'npm')

    project1 = Project.create!(url: 'https://github.com/base62/base62.js', registry_names: ['npm'], repository: { 'archived' => false })
    project2 = Project.create!(url: 'https://github.com/base62/archived', registry_names: ['npm'], repository: { 'archived' => true })

    assert_equal 1, fund.possible_projects.count
  end
end
