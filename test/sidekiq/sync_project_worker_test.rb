require 'test_helper'

class SyncProjectWorkerTest < ActiveSupport::TestCase
  test 'sync completes and saves funding from packages when other packages lack metadata' do
    project = create(:project, url: 'https://github.com/example/project', last_synced_at: nil)
    repository = {
      'full_name' => 'example/project',
      'html_url' => project.url,
      'host' => { 'name' => 'GitHub' },
      'owner' => 'example',
      'default_branch' => 'main',
      'topics' => [],
      'metadata' => {}
    }
    packages = [
      { 'name' => 'missing-metadata', 'registry' => { 'name' => 'npmjs.org' } },
      { 'name' => 'null-metadata', 'registry' => { 'name' => 'npmjs.org' }, 'metadata' => nil },
      { 'name' => 'funded-package', 'registry' => { 'name' => 'npmjs.org' },
        'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } }
    ]

    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, project.repos_api_url).to_return(body: repository.to_json)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/hosts/GitHub/owners/example').to_return(body: '{}')
    stub_request(:get, project.packages_url).to_return(body: packages.to_json)
    stub_request(:get, project.commits_api_url).to_return(body: '{}')
    stub_request(:get, "#{project.url}/raw/main/README.md").to_return(body: '# Example project')
    stub_request(:get, %r{https://[^/]+\.ecosyste\.ms/api/v1/.+/ping}).to_return(status: 200)

    SyncProjectWorker.new.perform(project.id)

    project.reload
    assert_not_nil project.last_synced_at
    assert_equal packages, project.packages
    assert_equal 'https://opencollective.com/example', project.funding_source.url
    assert_equal 'opencollective.com', project.funding_source.platform
  end
end
