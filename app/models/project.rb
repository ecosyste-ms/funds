class Project < ApplicationRecord

  validates :url, presence: true, uniqueness: { case_sensitive: false }

  has_many :project_allocations

  scope :active, -> { where("(repository ->> 'archived') = ?", 'false') }
  scope :archived, -> { where("(repository ->> 'archived') = ?", 'true') }

  scope :language, ->(language) { where("(repository ->> 'language') = ?", language) }
  scope :owner, ->(owner) { where("(repository ->> 'owner') = ?", owner) }
  scope :keyword, ->(keyword) { where("keywords @> ARRAY[?]::varchar[]", keyword) }
  scope :with_readme, -> { where.not(readme: nil) }
  scope :with_repository, -> { where.not(repository: {}) }
  scope :with_commits, -> { where.not(commits: nil) }
  scope :with_keywords, -> { where.not(keywords: []) }
  scope :without_keywords, -> { where(keywords: []) }
  scope :with_packages, -> { where.not(packages: [nil, []]) }

  def self.sync_least_recently_synced
    Project.where(last_synced_at: nil).or(Project.where("last_synced_at < ?", 1.day.ago)).order('last_synced_at asc nulls first').limit(500).each do |project|
      project.sync_async
    end
  end

  def self.sync_all
    Project.all.each do |project|
      project.sync_async
    end
  end

  def to_s
    name.presence || url
  end

  def repository_url
    repo_url = github_pages_to_repo_url(url)
    return repo_url if repo_url.present?
    url
  end

  def github_pages_to_repo_url(github_pages_url)
    return if github_pages_url.blank?
    match = github_pages_url.chomp('/').match(/https?:\/\/(.+)\.github\.io\/(.+)/)
    return nil unless match
  
    username = match[1]
    repo_name = match[2]
  
    "https://github.com/#{username}/#{repo_name}"
  end

  def first_created
    return unless repository.present?
    Time.parse(repository['created_at'])
  end

  def sync
    status = check_url
    return if status.blank?
    fetch_repository
    fetch_owner
    fetch_dependencies
    fetch_packages
    combine_keywords
    fetch_commits
    fetch_events
    fetch_issue_stats
    fetch_readme
    update(last_synced_at: Time.now)
    ping
  end

  def sync_async
    SyncProjectWorker.perform_async(id)
  end

  def check_url
    conn = Faraday.new(url: url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    update!(url: response.env.url.to_s) 
    # TODO avoid duplicates
  rescue ActiveRecord::RecordInvalid => e
    puts "Duplicate url #{url}"
    puts e.class
    destroy
    return nil
  rescue
    puts "Error checking url for #{url}"
    return nil
  end

  def combine_keywords
    all_keywords = []
    all_keywords += repository["topics"] if repository.present?
    all_keywords += packages.map{|p| p["keywords"]}.flatten if packages.present?
    self.keywords = all_keywords.reject(&:blank?).uniq { |keyword| keyword.downcase }.dup
    self.save
  rescue FrozenError
    puts "Error combining keywords for #{repository_url}"
  end

  def ping
    ping_urls.each do |url|
      Faraday.get(url) rescue nil
    end
  end

  def ping_urls
    ([repos_ping_url] + [issues_ping_url] + [commits_ping_url] + packages_ping_urls + [owner_ping_url]).compact.uniq
  end

  def repos_ping_url
    return unless repository.present?
    "https://repos.ecosyste.ms/api/v1/hosts/#{repository['host']['name']}/repositories/#{repository['full_name']}/ping"
  end

  def issues_ping_url
    return unless repository.present?
    "https://issues.ecosyste.ms/api/v1/hosts/#{repository['host']['name']}/repositories/#{repository['full_name']}/ping"
  end

  def commits_ping_url
    return unless repository.present?
    "https://commits.ecosyste.ms/api/v1/hosts/#{repository['host']['name']}/repositories/#{repository['full_name']}/ping"
  end

  def packages_ping_urls
    return [] unless packages.present?
    packages.map do |package|
      "https://packages.ecosyste.ms/api/v1/registries/#{package['registry']['name']}/packages/#{package['name']}/ping"
    end
  end

  def owner_ping_url
    return unless repository.present?
    "https://repos.ecosyste.ms/api/v1/hosts/#{repository['host']['name']}/owner/#{repository['owner']}/ping"
  end

  def description
    return read_attribute(:description) if read_attribute(:description).present?
    return unless repository.present?
    repository["description"]
  end

  def repos_api_url
    "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=#{repository_url}"
  end

  def repos_url
    return unless repository.present?
    "https://repos.ecosyste.ms/hosts/#{repository['host']['name']}/repositories/#{repository['full_name']}"
  end

  def fetch_repository
    conn = Faraday.new(url: repos_api_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    self.repository = JSON.parse(response.body)
    self.save
  rescue
    puts "Error fetching repository for #{repository_url}"
  end

  def owner_api_url
    return unless repository.present?
    return unless repository["owner"].present?
    return unless repository["host"].present?
    return unless repository["host"]["name"].present?
    "https://repos.ecosyste.ms/api/v1/hosts/#{repository['host']['name']}/owners/#{repository['owner']}"
  end

  def owner_url
    return unless repository.present?
    return unless repository["owner"].present?
    return unless repository["host"].present?
    return unless repository["host"]["name"].present?
    "https://repos.ecosyste.ms/hosts/#{repository['host']['name']}/owners/#{repository['owner']}"
  end

  def fetch_owner
    return unless owner_api_url.present?
    conn = Faraday.new(url: owner_api_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    self.owner = JSON.parse(response.body)
    self.save
  rescue
    puts "Error fetching owner for #{repository_url}"
  end

  def timeline_url
    return unless repository.present?
    return unless repository["host"]["name"] == "GitHub"

    "https://timeline.ecosyste.ms/api/v1/events/#{repository['full_name']}/summary"
  end

  def fetch_events
    return unless timeline_url.present?
    conn = Faraday.new(url: timeline_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    summary = JSON.parse(response.body)

    conn = Faraday.new(url: timeline_url+'?after='+1.year.ago.to_fs(:iso8601)) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    last_year = JSON.parse(response.body)

    self.events = {
      "total" => summary,
      "last_year" => last_year
    }
    self.save
  rescue
    puts "Error fetching events for #{repository_url}"
  end

  # TODO fetch repo dependencies
  # TODO fetch repo tags

  def packages_url
    "https://packages.ecosyste.ms/api/v1/packages/lookup?repository_url=#{repository_url}"
  end

  def fetch_packages
    conn = Faraday.new(url: packages_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    self.packages = JSON.parse(response.body)
    self.save
  rescue
    puts "Error fetching packages for #{repository_url}"
  end

  def commits_api_url
    "https://commits.ecosyste.ms/api/v1/repositories/lookup?url=#{repository_url}"
  end

  def commits_url
    "https://commits.ecosyste.ms/repositories/lookup?url=#{repository_url}"
  end

  def fetch_commits
    conn = Faraday.new(url: commits_api_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get
    return unless response.success?
    self.commits = JSON.parse(response.body)
    self.save
  rescue
    puts "Error fetching commits for #{repository_url}"
  end

  def committers_names
    return [] unless commits.present?
    return [] unless commits["committers"].present?
    commits["committers"].map{|c| c["name"].downcase }.uniq
  end

  def committers
    return [] unless commits.present?
    return [] unless commits["committers"].present?
    commits["committers"].map{|c| [c["name"].downcase, c["count"]]}.each_with_object(Hash.new {|h,k| h[k] = 0}) { |(x,d),h| h[x] += d }
  end

  def raw_committers
    return [] unless commits.present?
    return [] unless commits["committers"].present?
    commits["committers"]
  end

  def fetch_dependencies
    return unless repository.present?
    conn = Faraday.new(url: repository['manifests_url']) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get
    return unless response.success?
    self.dependencies = JSON.parse(response.body)
    self.save
  rescue
    puts "Error fetching dependencies for #{repository_url}"
  end

  def fetch_dependent_repos
    return unless packages.present?
    dependent_repos = []
    packages.each do |package|
      # TODO paginate
      # TODO group dependencies by repo
      dependent_repos_url = "https://repos.ecosyste.ms/api/v1/usage/#{package["ecosystem"]}/#{package["name"]}/dependencies"
      conn = Faraday.new(url: dependent_repos_url)
      response = conn.get
      return unless response.success?
      dependent_repos += JSON.parse(response.body)
    end
    self.dependent_repos = dependent_repos.uniq
    self.save
  end

  def issues_api_url
    "https://issues.ecosyste.ms/api/v1/repositories/lookup?url=#{repository_url}"
  end

  def issue_stats_url
    "https://issues.ecosyste.ms/repositories/lookup?url=#{repository_url}"
  end

  def fetch_issue_stats
    conn = Faraday.new(url: issues_api_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get
    return unless response.success?
    self.issue_stats = JSON.parse(response.body)
    self.save
  rescue => e
    puts "Error fetching issues for #{repository_url}"
    puts e
  end

  def language
    return unless repository.present?
    repository['language']
  end

  def language_with_default
    language.presence || 'Unknown'
  end

  def issue_stats
    i = read_attribute(:issue_stats) || {}
    JSON.parse(i.to_json, object_class: OpenStruct)
  end

  def language
    return unless repository.present?
    repository['language']
  end

  def owner_name
    return unless repository.present?
    repository['owner']
  end

  def avatar_url
    return unless repository.present?
    repository['icon_url']
  end

  def stars
    return 0 unless repository.present?
    repository['stargazers_count'] || 0
  end
  
  def packages_count
    return 0 unless packages.present?
    packages.length
  end

  def monthly_downloads
    return 0 unless packages.present?
    packages.select{|p| p['downloads_period'] == 'last-month' }.map{|p| p["downloads"] || 0 }.sum
  end

  def downloads
    return 0 unless packages.present?
    packages.map{|p| p["downloads"] || 0 }.sum
  end

  def dependent_repos_count
    return 0 unless packages.present?
    packages.map{|p| p["dependent_repos_count"] || 0 }.sum
  end

  def dependent_packages_count
    return 0 unless packages.present?
    packages.map{|p| p["dependent_packages_count"] || 0 }.sum
  end

  def issue_associations
    return [] unless issue_stats.present?
    (issue_stats['issue_author_associations_count'].keys + issue_stats['pull_request_author_associations_count'].keys).uniq
  end

  def repository_license
    return nil unless repository.present?
    repository['license'] || repository.dig('metadata', 'files', 'license')
  end

  def packages_licenses
    return [] unless packages.present?
    packages.map{|p| p['licenses'] }.compact
  end

  def readme_license
    return nil unless readme.present?
    readme_image_urls.select{|u| u.downcase.include?('license') }.any?
  end

  def open_source_license?
    (packages_licenses + [repository_license] + [readme_license]).compact.uniq.any?
  end

  def past_year_total_commits
    return 0 unless commits.present?
    commits['past_year_total_commits'] || 0
  end

  def past_year_total_commits_exclude_bots
    return 0 unless commits.present?
    past_year_total_commits - past_year_total_bot_commits
  end

  def past_year_total_bot_commits
    return 0 unless commits.present?
    commits['past_year_total_bot_commits'].presence || 0
  end

  def commits_this_year?
    return false unless repository.present?
    if commits.present?
      past_year_total_commits_exclude_bots > 0
    else
      return false unless repository['pushed_at'].present?
      repository['pushed_at'] > 1.year.ago 
    end
  end

  def issues_this_year?
    return false unless issue_stats.present?
    return false unless issue_stats['past_year_issues_count'].present?
    (issue_stats['past_year_issues_count'] - issue_stats['past_year_bot_issues_count']) > 0
  end

  def pull_requests_this_year?
    return false unless issue_stats.present?
    return false unless issue_stats['past_year_pull_requests_count'].present?
    (issue_stats['past_year_pull_requests_count'] - issue_stats['past_year_bot_pull_requests_count']) > 0
  end

  def archived?
    return false unless repository.present?
    repository['archived']
  end

  def active?
    return false if archived?
    commits_this_year? || issues_this_year? || pull_requests_this_year?
  end

  def fork?
    return false unless repository.present?
    repository['fork']
  end

  def download_url
    return unless repository.present?
    repository['download_url']
  end

  def archive_url(path)
    return unless download_url.present?
    "https://archives.ecosyste.ms/api/v1/archives/contents?url=#{download_url}&path=#{path}"
  end


  def readme_file_name
    return unless repository.present?
    return unless repository['metadata'].present?
    return unless repository['metadata']['files'].present?
    repository['metadata']['files']['readme']
  end

  def readme_is_markdown?
    return unless readme_file_name.present?
    readme_file_name.downcase.ends_with?('.md') || readme_file_name.downcase.ends_with?('.markdown')
  end

  def fetch_readme
    if readme_file_name.blank? || download_url.blank?
      fetch_readme_fallback
    else
      return unless download_url.present?
      conn = Faraday.new(url: archive_url(readme_file_name)) do |faraday|
        faraday.response :follow_redirects
        faraday.adapter Faraday.default_adapter
      end
      response = conn.get
      return unless response.success?
      json = JSON.parse(response.body)

      self.readme = json['contents']
      self.save
    end
  rescue
    puts "Error fetching readme for #{repository_url}"
    fetch_readme_fallback
  end

  def fetch_readme_fallback
    file_name = readme_file_name.presence || 'README.md'
    conn = Faraday.new(url: raw_url(file_name)) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    self.readme = response.body
    self.save
  rescue
    puts "Error fetching readme for #{repository_url}"
  end

  def readme_url
    return unless repository.present?
    "#{repository['html_url']}/blob/#{repository['default_branch']}/#{readme_file_name}"
  end




  def blob_url(path)
    return unless repository.present?
    "#{repository['html_url']}/blob/#{repository['default_branch']}/#{path}"
  end 

  def raw_url(path)
    return unless repository.present?
    "#{repository['html_url']}/raw/#{repository['default_branch']}/#{path}"
  end 

  def sync_issues
    conn = Faraday.new(url: issues_api_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get
    return unless response.success?
    issues_list_url = JSON.parse(response.body)['issues_url'] + '?per_page=1000&pull_request=false'
    # issues_list_url = issues_list_url + '&updated_after=' + last_synced_at.to_fs(:iso8601) if last_synced_at.present?

    conn = Faraday.new(url: issues_list_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end
    response = conn.get
    return unless response.success?
    
    issues_json = JSON.parse(response.body)

    # TODO pagination
    # TODO upsert (plus unique index)

    issues_json.each do |issue|
      i = issues.find_or_create_by(number: issue['number']) 
      i.assign_attributes(issue)
      i.save(touch: false)
    end
  end

  def funding_links
    @funding_links ||= (package_funding_links + repo_funding_links + owner_funding_links + readme_funding_links).uniq
  end

  def package_funding_links
    return [] unless packages.present?
    packages.map{|pkg| pkg['metadata']['funding'] }.compact.map{|f| f.is_a?(Hash) ? f['url'] : f }.flatten.compact
  end

  def owner_funding_links
    return [] if repository.blank? || repository['owner_record'].blank? ||  repository['owner_record']["metadata"].blank?
    return [] unless repository['owner_record']["metadata"]['has_sponsors_listing']
    ["https://github.com/sponsors/#{repository['owner_record']['login']}"]
  end

  def repo_funding_links
    return [] if repository.blank? || repository['metadata'].blank? ||  repository['metadata']["funding"].blank?
    return [] if repository['metadata']["funding"].is_a?(String)
    repository['metadata']["funding"].map do |key,v|
      next if v.blank?
      case key
      when "github"
        Array(v).map{|username| "https://github.com/sponsors/#{username}" }
      when "tidelift"
        "https://tidelift.com/funding/github/#{v}"
      when "community_bridge"
        "https://funding.communitybridge.org/projects/#{v}"
      when "issuehunt"
        "https://issuehunt.io/r/#{v}"
      when "open_collective"
        "https://opencollective.com/#{v}"
      when "ko_fi"
        "https://ko-fi.com/#{v}"
      when "liberapay"
        "https://liberapay.com/#{v}"
      when "custom"
        v
      when "otechie"
        "https://otechie.com/#{v}"
      when "patreon"
        "https://patreon.com/#{v}"
      when "polar"
        "https://polar.sh/#{v}"
      when 'buy_me_a_coffee'
        "https://buymeacoffee.com/#{v}"
      else
        v
      end
    end.flatten.compact
  end

  def readme_urls
    return [] unless readme.present?
    urls = URI.extract(readme.gsub(/[\[\]]/, ' '), ['http', 'https']).uniq
    # remove trailing garbage
    urls.map{|u| u.gsub(/\:$/, '').gsub(/\*$/, '').gsub(/\.$/, '').gsub(/\,$/, '').gsub(/\*$/, '').gsub(/\)$/, '').gsub(/\)$/, '').gsub('&nbsp;','') }
  end

  def readme_domains
    readme_urls.map{|u| URI.parse(u).host rescue nil }.compact.uniq
  end

  def funding_domains
    ['opencollective.com', 'ko-fi.com', 'liberapay.com', 'patreon.com', 'otechie.com', 'issuehunt.io', 
    'communitybridge.org', 'tidelift.com', 'buymeacoffee.com', 'paypal.com', 'paypal.me','givebutter.com', 'polar.sh']
  end

  def unique_funding_domains
    funding_links.map{|u| URI.parse(u).host.gsub(/^www\./, '').gsub('paypal.me', 'paypal.com') rescue nil }.compact.uniq
  end

  def preferred_funding_platform
    # pick the first funding platform from unique_funding_domains, preferring opencollective.com, otherwise prefer github.com if it's there
    unique_funding_domains.find{|d| d == 'opencollective.com' } || unique_funding_domains.find{|d| d == 'github.com' } || unique_funding_domains.first || 'Unknown'
  end

  def readme_funding_links
    urls = readme_urls.select{|u| funding_domains.any?{|d| u.include?(d) } || u.include?('github.com/sponsors') }.reject{|u| ['.svg', '.png'].include? File.extname(URI.parse(u).path) }
    # remove anchors
    urls = urls.map{|u| u.gsub(/#.*$/, '') }.uniq
    # remove sponsor/9/website from open collective urls
    urls = urls.map{|u| u.gsub(/\/sponsor\/\d+\/website$/, '') }.uniq
    # remove backer/9/website from open collective urls
    urls = urls.map{|u| u.gsub(/\/backer\/\d+\/website$/, '') }.uniq
  end

  


end