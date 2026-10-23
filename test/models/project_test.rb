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

  test 'sync stores funding links, dropping github sponsors accounts without a listing' do
    FundingSource.instance_variable_set(:@github_sponsors_logins, nil)
    project = create(:project, url: 'https://github.com/example/synced', repository: {
      'topics' => [],
      'metadata' => { 'funding' => { 'github' => ['listed', 'unlisted'], 'patreon' => 'synced' } }
    })
    stub_request(:any, /.*/).to_return(status: 404)
    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, 'https://sponsors.ecosyste.ms/api/v1/accounts/sponsor_logins').to_return(status: 200, body: ['listed'].to_json)

    project.sync

    assert_equal ['https://github.com/sponsors/listed', 'https://patreon.com/synced'], project.reload.funding_links.sort
    assert_equal 'https://github.com/sponsors/listed', project.funding_source.url
  ensure
    FundingSource.instance_variable_set(:@github_sponsors_logins, nil)
  end

  test 'sync keeps stored funding links when the sponsor list fetch fails' do
    FundingSource.instance_variable_set(:@github_sponsors_logins, nil)
    project = create(:project, url: 'https://github.com/example/failed-fetch', funding_links: ['https://github.com/sponsors/listed'], repository: {
      'topics' => [],
      'metadata' => { 'funding' => { 'github' => 'listed' } }
    })
    stub_request(:any, /.*/).to_return(status: 404)
    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, 'https://sponsors.ecosyste.ms/api/v1/accounts/sponsor_logins').to_return(status: 500)

    assert_raises(RuntimeError) { project.sync }
    assert_equal ['https://github.com/sponsors/listed'], project.reload.funding_links
    assert_nil FundingSource.instance_variable_get(:@github_sponsors_logins)
  ensure
    FundingSource.instance_variable_set(:@github_sponsors_logins, nil)
  end

  test 'reading funding links makes no http requests' do
    project = create(:project, repository: { 'metadata' => { 'funding' => { 'github' => 'someone' } } }, funding_links: ['https://github.com/sponsors/someone'])

    assert_equal ['https://github.com/sponsors/someone'], Project.find(project.id).funding_links
    assert_equal 'github.com', project.preferred_funding_platform
  end

  test 'total funded uses a database aggregate' do
    project = create(:project)
    fund = create(:fund)
    allocation = create(:allocation, fund: fund)
    create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 100, paid_at: Time.current)
    create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 250, paid_at: Time.current)
    create(:project_allocation, project: project, fund: fund, allocation: allocation, amount_cents: 9000)

    queries = record_select_queries do
      assert_equal 350, project.total_funded
    end

    assert_equal 1, queries.length
    assert_includes queries.first, 'SUM("project_allocations"."amount_cents")'
  end
end
