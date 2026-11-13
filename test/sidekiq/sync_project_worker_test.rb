require 'test_helper'

class SyncProjectWorkerTest < ActiveSupport::TestCase
  test 'duplicate redirects become aliases without moving allocations or contact details' do
    canonical = create(:project, url: 'https://github.com/example/canonical', last_synced_at: nil)
    project = create(:project, url: 'https://github.com/example/old', last_synced_at: nil,
      confirmed_contact_email: 'maintainer@example.com', confirmed_contact_recipient: 'github:old', funding_rejected: true)
    project_allocation = create(:project_allocation, project: project, paid_at: Time.current)
    original_url = project.url
    redirected_url = canonical.url.sub('/example/', '/EXAMPLE/')
    stub_request(:get, original_url).to_return(status: 301, headers: { 'Location' => redirected_url })
    stub_request(:get, redirected_url).to_return(status: 200)
    stub_request(:get, canonical.url).to_return(status: 200)
    stub_project_metadata(canonical)

    freeze_time do
      SyncProjectWorker.new.perform(project.id)

      project.reload
      canonical.reload
      assert_equal canonical, project.canonical_project
      assert_equal original_url, project.url
      assert_equal Time.current, project.last_synced_at
      assert_equal canonical.repository, project.repository
      assert_equal canonical.funding_links, project.funding_links
      assert_equal 'https://opencollective.com/canonical', project.funding_source.url
      assert_equal project.id, project_allocation.reload.project_id
      assert_equal 'maintainer@example.com', project.confirmed_contact_email
      assert_equal 'github:old', project.confirmed_contact_recipient
      assert project.funding_rejected?

      travel 2.days
      SyncProjectWorker.clear
      Project.sync_least_recently_synced
      assert_equal [[canonical.id]], SyncProjectWorker.jobs.map { |job| job['args'] }
    end
  ensure
    SyncProjectWorker.clear
  end

  test 'allocated aliases refresh through the canonical project without checking the old URL again' do
    canonical = create(:project, url: 'https://github.com/example/canonical')
    project = create(:project, canonical_project: canonical, funding_links: ['https://patreon.com/outdated'])
    create(:project_allocation, project: project)
    stub_request(:get, canonical.url).to_return(status: 200)
    stub_project_metadata(canonical)

    freeze_time do
      SyncProjectWorker.clear
      Project.sync_projects_with_allocations
      SyncProjectWorker.drain

      assert_equal Time.current, canonical.reload.last_synced_at
      assert_equal Time.current, project.reload.last_synced_at
      assert_equal ['https://opencollective.com/canonical'], project.funding_links
      assert_equal canonical.read_attribute(:funding_source_id), project.read_attribute(:funding_source_id)
      assert_not_requested :get, project.url
    end
  ensure
    SyncProjectWorker.clear
  end

  test 'a failed canonical refresh preserves alias metadata and its last successful sync' do
    canonical = create(:project)
    project = create(:project, canonical_project: canonical, funding_links: ['https://patreon.com/stored'])
    last_synced_at = project.last_synced_at
    stub_request(:get, canonical.url).to_return(status: 503)

    freeze_time do
      SyncProjectWorker.new.perform(project.id)

      assert_equal Time.current, project.reload.last_sync_attempted_at
      assert_equal Time.current, canonical.reload.last_sync_attempted_at
      assert_equal last_synced_at, project.last_synced_at
      assert_equal ['https://patreon.com/stored'], project.funding_links
    end
  end

  test 'alias chains refresh through their final canonical project' do
    canonical = create(:project, url: 'https://github.com/example/canonical')
    intermediate = create(:project, canonical_project: canonical)
    project = create(:project, canonical_project: intermediate)
    stub_request(:get, canonical.url).to_return(status: 200)
    stub_project_metadata(canonical)

    SyncProjectWorker.new.perform(project.id)

    assert_equal ['https://opencollective.com/canonical'], project.reload.funding_links
    assert_equal canonical.reload.last_synced_at, project.last_synced_at
    assert_not_requested :get, project.url
    assert_not_requested :get, intermediate.url
  end

  test 'alias cycles return without changing successful sync timestamps' do
    project = create(:project, last_synced_at: nil)
    other = create(:project, canonical_project: project, last_synced_at: nil)
    project.update!(canonical_project: other)

    SyncProjectWorker.new.perform(project.id)

    assert_nil project.reload.last_synced_at
    assert_nil other.reload.last_synced_at
    assert_not_nil project.last_sync_attempted_at
    assert_not_nil other.last_sync_attempted_at
  end

  test 'failed URL checks record an attempt without changing the last successful sync' do
    project = create(:project, last_synced_at: 1.year.ago)
    last_synced_at = project.last_synced_at
    stub_request(:get, project.url).to_return(status: 503)

    freeze_time do
      SyncProjectWorker.new.perform(project.id)

      assert_equal Time.current, project.reload.last_sync_attempted_at
      assert_equal last_synced_at, project.last_synced_at
    end
  end

  test 'connection failures also record an attempt' do
    project = create(:project, last_synced_at: nil)
    stub_request(:get, project.url).to_timeout

    freeze_time do
      SyncProjectWorker.new.perform(project.id)

      assert_equal Time.current, project.reload.last_sync_attempted_at
      assert_nil project.last_synced_at
    end
  end

  test 'exceptions during metadata refresh retain the attempt for scheduling' do
    FundingSource.instance_variable_set(:@github_sponsors_logins, nil)
    project = create(:project, last_synced_at: nil, repository: {
      'topics' => [], 'metadata' => { 'funding' => { 'github' => 'listed' } }
    })
    stub_request(:any, /.*/).to_return(status: 404)
    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, 'https://sponsors.ecosyste.ms/api/v1/accounts/sponsor_logins').to_return(status: 500)

    freeze_time do
      assert_raises(RuntimeError) { SyncProjectWorker.new.perform(project.id) }

      assert_equal Time.current, project.reload.last_sync_attempted_at
      assert_nil project.last_synced_at
      SyncProjectWorker.clear
      Project.sync_least_recently_synced
      assert_empty SyncProjectWorker.jobs
    end
  ensure
    FundingSource.instance_variable_set(:@github_sponsors_logins, nil)
    SyncProjectWorker.clear
  end

  test 'redirects to an unused URL still update the project and complete the sync' do
    project = create(:project, url: 'https://github.com/example/old-name', last_synced_at: nil)
    destination = 'https://github.com/example/new-name'
    stub_request(:any, /.*/).to_return(status: 404)
    stub_request(:get, project.url).to_return(status: 301, headers: { 'Location' => destination })
    stub_request(:get, destination).to_return(status: 200)

    freeze_time do
      SyncProjectWorker.new.perform(project.id)

      assert_equal destination, project.reload.url
      assert_equal Time.current, project.last_sync_attempted_at
      assert_equal Time.current, project.last_synced_at
    end
  end

  test 'repeated failures allow previously synced projects into the next scheduler batch' do
    failed_projects = create_list(:project, 100, last_synced_at: nil)
    stale_project = create(:project, last_synced_at: 1.year.ago)
    recent_project = create(:project, last_synced_at: 1.hour.ago)
    stub_request(:get, %r{https://github.com/}).to_return(status: 503)

    freeze_time do
      SyncProjectWorker.clear
      Project.sync_least_recently_synced
      assert_equal failed_projects.map(&:id).sort, SyncProjectWorker.jobs.map { |job| job['args'].first }.sort
      SyncProjectWorker.drain

      2.times do
        travel 2.days
        SyncProjectWorker.clear
        Project.sync_least_recently_synced
        selected_ids = SyncProjectWorker.jobs.map { |job| job['args'].first }
        assert_equal 100, selected_ids.length
        assert_equal stale_project.id, selected_ids.first
        assert_includes selected_ids, recent_project.id
        failed_projects.each { |project| SyncProjectWorker.new.perform(project.id) }
      end
    end
  ensure
    SyncProjectWorker.clear
  end

  test 'failed projects wait a day before the regular scheduler retries them' do
    project = create(:project, last_synced_at: nil)
    stub_request(:get, project.url).to_return(status: 404)

    freeze_time do
      SyncProjectWorker.new.perform(project.id)
      travel 23.hours
      SyncProjectWorker.clear
      Project.sync_least_recently_synced
      assert_empty SyncProjectWorker.jobs

      travel 2.hours
      Project.sync_least_recently_synced
      assert_equal [[project.id]], SyncProjectWorker.jobs.map { |job| job['args'] }
    end
  ensure
    SyncProjectWorker.clear
  end

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
      { 'id' => 1, 'name' => 'missing-metadata', 'registry' => { 'name' => 'npmjs.org' } },
      { 'id' => 2, 'name' => 'null-metadata', 'registry' => { 'name' => 'npmjs.org' }, 'metadata' => nil },
      { 'id' => 3, 'name' => 'funded-package', 'registry' => { 'name' => 'npmjs.org' },
        'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
    ]

    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, project.repos_api_url).to_return(body: repository.to_json)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/hosts/GitHub/owners/example').to_return(body: '{}')

    packages_url_p1 = "#{project.packages_url}&page=1"

    # duplicate items in packages here to ensure dedupe is performed while fetching packages.
    packages_with_duplicates = packages + [packages.first, packages.last]

    stub_request(:get, packages_url_p1).to_return(body: packages_with_duplicates.to_json)
    stub_request(:get, project.commits_api_url).to_return(body: '{}')
    stub_request(:get, "#{project.url}/raw/main/README.md").to_return(body: '# Example project')
    stub_request(:get, %r{https://[^/]+\.ecosyste\.ms/api/v1/.+/ping}).to_return(status: 200)

    SyncProjectWorker.new.perform(project.id)

    project.reload
    assert_not_nil project.last_synced_at
    assert_not_nil project.last_sync_attempted_at
    assert_equal packages, project.packages
    assert_equal 3, project.packages.length
    assert_equal 'https://opencollective.com/example', project.funding_source.url
    assert_equal 'opencollective.com', project.funding_source.platform
  end

  test 'sync completes and saves packages from all pages of packages lookup' do
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
        { 'id' => 1, 'name' => 'funded-package-1', 'registry' => { 'name' => 'npmjs.org' },
        'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
        { 'id' => 2, 'name' => 'funded-package-2', 'registry' => { 'name' => 'npmjs.org' },
        'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
        { 'id' => 3, 'name' => 'funded-package-3', 'registry' => { 'name' => 'npmjs.org' },
        'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
    ]

    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, project.repos_api_url).to_return(body: repository.to_json)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/hosts/GitHub/owners/example').to_return(body: '{}')

    # page 3 returns empty array so fetching ends there.
    packages_url_p1 = "#{project.packages_url}&page=1"
    packages_url_p2 = "#{project.packages_url}&page=2"
    packages_url_p3 = "#{project.packages_url}&page=3"

    # duplicate items in packages here to ensure dedupe is performed while fetching packages.
    stub_request(:get, packages_url_p1).to_return(
      body: [packages[0], packages[1], packages[0]].to_json,
      headers: { 'Link' => "<#{packages_url_p1}>; rel=\"first\", <#{packages_url_p2}>; rel=\"next\"" }
    )
    stub_request(:get, packages_url_p2).to_return(
      body: [packages[2], packages[1], packages[1]].to_json,
      headers: { 'Link' => "#{packages_url_p3};rel=next" }
    )
    stub_request(:get, packages_url_p3).to_return(body: [].to_json)
    stub_request(:get, project.commits_api_url).to_return(body: '{}')
    stub_request(:get, "#{project.url}/raw/main/README.md").to_return(body: '# Example project')
    stub_request(:get, %r{https://[^/]+\.ecosyste\.ms/api/v1/.+/ping}).to_return(status: 200)

    SyncProjectWorker.new.perform(project.id)

    project.reload
    assert_not_nil project.last_synced_at
    assert_not_nil project.last_sync_attempted_at
    assert_equal packages, project.packages
    assert_equal 3, project.packages.length
    assert_equal 'https://opencollective.com/example', project.funding_source.url
    assert_equal 'opencollective.com', project.funding_source.platform
  end

  test 'sync completes and replaces stored packages only after successful packages lookup' do
    existing_packages = [
      { 'id' => 1, 'name' => 'funded-package-1', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
      { 'id' => 2, 'name' => 'funded-package-2', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
      { 'id' => 3, 'name' => 'funded-package-3', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
      { 'id' => 4, 'name' => 'funded-package-4', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
    ]
    project = create(:project, url: 'https://github.com/example/project', last_synced_at: nil, packages: existing_packages)
    repository = {
      'full_name' => 'example/project',
      'html_url' => project.url,
      'host' => { 'name' => 'GitHub' },
      'owner' => 'example',
      'default_branch' => 'main',
      'topics' => [],
      'metadata' => {}
    }
    stub_request(:get, project.url).to_return(status: 200)
    stub_request(:get, project.repos_api_url).to_return(body: repository.to_json)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/hosts/GitHub/owners/example').to_return(body: '{}')

    # Package lookup API throws an error on page 2, so stored packages are not replaced with the new packages.
    new_packages = existing_packages + [
      { 'id' => 5, 'name' => 'new-funded-package-1', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
      { 'id' => 6, 'name' => 'new-funded-package-2', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
      { 'id' => 7, 'name' => 'new-funded-package-3', 'registry' => { 'name' => 'npmjs.org' },
      'metadata' => { 'funding' => { 'url' => 'https://opencollective.com/example' } } },
    ]
    packages_url_p1 = "#{project.packages_url}&page=1"
    packages_url_p2 = "#{project.packages_url}&page=2"
    stub_request(:get, packages_url_p1).to_return(
      body: new_packages.to_json,
      headers: { 'Link' => "#{packages_url_p2}; rel=\"next\"" }
    )
    stub_request(:get, packages_url_p2).to_return(status: 500)

    stub_request(:get, project.commits_api_url).to_return(body: '{}')
    stub_request(:get, "#{project.url}/raw/main/README.md").to_return(body: '# Example project')
    stub_request(:get, %r{https://[^/]+\.ecosyste\.ms/api/v1/.+/ping}).to_return(status: 200)

    SyncProjectWorker.new.perform(project.id)
    project.reload

    assert_not_nil project.last_synced_at
    assert_not_nil project.last_sync_attempted_at
    assert_equal existing_packages, project.packages
    assert_equal 4, project.packages.length
    assert_equal 'https://opencollective.com/example', project.funding_source.url
    assert_equal 'opencollective.com', project.funding_source.platform
  end

  def stub_project_metadata(project)
    repository = {
      'full_name' => 'example/canonical', 'html_url' => project.url,
      'host' => { 'name' => 'GitHub' }, 'owner' => 'example', 'default_branch' => 'main',
      'topics' => [], 'metadata' => { 'funding' => { 'open_collective' => 'canonical' } }
    }
    stub_request(:get, project.repos_api_url).to_return(body: repository.to_json)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/hosts/GitHub/owners/example').to_return(body: '{}')
    stub_request(:get, "#{project.packages_url}&page=1").to_return(body: '[]')
    stub_request(:get, project.commits_api_url).to_return(body: '{}')
    stub_request(:get, "#{project.url}/raw/main/README.md").to_return(body: '# Canonical project')
    stub_request(:get, %r{https://[^/]+\.ecosyste\.ms/api/v1/.+/ping}).to_return(status: 200)
  end
end
