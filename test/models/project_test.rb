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

  test 'set funding links ignores non-url values from unknown funding.yml keys' do
    project = create(:project, repository: { 'metadata' => { 'funding' => {
      'github' => nil,
      'open_collective' => 'hiddify',
      'custom' => ['https://github.com/hiddify/hiddify-manager/wiki/Support', 42],
      'bitcoin' => '3Epy7jyUUCVb1w12MNTu2JFVVhmfpr4EGX',
      'ethereum' => 1377979888499107190715896424743981346969345115104,
      'other' => 'https://example.com/donate'
    } } })

    project.set_funding_links

    assert_equal ['https://opencollective.com/hiddify', 'https://example.com/donate'], project.reload.funding_links
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

  test 'stored preferred funding link and platform come from the stored funding source' do
    funding_source = create(:funding_source, url: 'https://patreon.com/stored', platform: 'patreon.com')
    project = create(
      :project,
      funding_links: ['https://opencollective.com/readme-funded'],
      funding_source: funding_source
    )

    assert_equal 'https://patreon.com/stored', project.stored_preferred_funding_link
    assert_equal 'patreon.com', project.stored_preferred_funding_platform
  end

  test 'stored preferred funding link and platform fall back to funding links without a stored source' do
    project = create(
      :project,
      funding_links: ['https://opencollective.com/readme-funded', 'https://patreon.com/readme-funded']
    )

    assert_equal 'https://opencollective.com/readme-funded', project.stored_preferred_funding_link
    assert_equal 'opencollective.com', project.stored_preferred_funding_platform
  end

  test 'stored preferred funding link is nil and platform unknown without any funding' do
    project = create(:project)

    assert_nil project.stored_preferred_funding_link
    assert_equal 'Unknown', project.stored_preferred_funding_platform
  end

  test 'open collective match returns the stored open collective url' do
    funding_source = create(:funding_source, url: 'https://opencollective.com/matched', platform: 'opencollective.com')
    project = create(:project, funding_source: funding_source)

    assert_equal 'https://opencollective.com/matched', project.open_collective_match
  end

  test 'open collective match is nil for a non open collective funding source' do
    funding_source = create(:funding_source, url: 'https://patreon.com/stored', platform: 'patreon.com')
    project = create(:project, funding_source: funding_source)

    assert_nil project.open_collective_match
  end

  test 'open collective match is nil without a funding source' do
    project = create(:project, funding_links: ['https://opencollective.com/readme-funded'])

    assert_nil project.open_collective_match
  end

  test 'open collective alternative returns the stored match for a github sponsors only project' do
    funding_source = create(:funding_source, url: 'https://opencollective.com/mapped-oc', platform: 'opencollective.com')
    project = create(
      :project,
      funding_links: ['https://github.com/sponsors/mappeduser'],
      funding_source: funding_source
    )

    assert_equal 'https://opencollective.com/mapped-oc', project.open_collective_alternative
  end

  test 'open collective alternative is nil without a github sponsors link' do
    funding_source = create(:funding_source, url: 'https://opencollective.com/matched', platform: 'opencollective.com')
    project = create(:project, funding_source: funding_source)

    assert_nil project.open_collective_alternative
  end

  test 'open collective alternative is nil when the match is already in funding links' do
    funding_source = create(:funding_source, url: 'https://opencollective.com/mapped-oc', platform: 'opencollective.com')
    project = create(
      :project,
      funding_links: ['https://github.com/sponsors/mappeduser', 'https://opencollective.com/mapped-oc'],
      funding_source: funding_source
    )

    assert_includes project.funding_links, 'https://opencollective.com/mapped-oc'
    assert_nil project.open_collective_alternative
  end
end
