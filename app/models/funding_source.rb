class FundingSource < ApplicationRecord
  include EcosystemsApiClient
  validates :url, presence: true

  has_many :projects
  has_many :project_allocations

  APPROVED_PLATFORMS = ['opencollective.com', 'github.com', 'patreon.com', 
  'liberapay.com', 'ko-fi.com', 'funding.communitybridge.org', 'buymeacoffee.com', 'paypal.com']
  
  scope :platform, ->(platform) { where(platform: platform) }
  scope :approved, -> { where(platform: APPROVED_PLATFORMS) }
  
  scope :with_project_allocations, -> { where('EXISTS (SELECT 1 FROM project_allocations WHERE project_allocations.funding_source_id = funding_sources.id)') }

  def self.sync_all
    FundingSource.with_project_allocations.approved.find_each(&:sync_all)
  end

  def self.open_collective_github_sponsors_mapping
    @open_collective_github_sponsors_mapping ||= begin
      url = 'https://raw.githubusercontent.com/opencollective/opencollective-tools/refs/heads/main/github-sponsors/csv-import-mapping.json'
      response = Faraday.get(url)
      JSON.parse(response.body)
    rescue
      {}
    end
  end

  def self.github_sponsors_logins
    @github_sponsors_logins ||= begin
      url = 'https://sponsors.ecosyste.ms/api/v1/accounts/sponsor_logins'
      response = ecosystems_api_request(url)
      JSON.parse(response.body)
    rescue
      []  
    end
  end

  def self.has_open_collective_alternative?(name)
    FundingSource.open_collective_github_sponsors_mapping[name]
  end

  def has_open_collective_alternative?
    return unless platform == 'github.com'
      
    oc_alt = FundingSource.open_collective_github_sponsors_mapping[name]
    oc_alt.present?
  end

  def approved?
    APPROVED_PLATFORMS.include?(platform)
  end

  def clean_url
    url.strip.chomp.gsub(/\[\"([^\"]+)\"\]/, '\1') # remove square brackets for vllm project with invalid funding.yml
  end

  def name
    case platform
    when 'github.com'
      URI.parse(clean_url).path.split('/')[2]
    when 'opencollective.com'
      URI.parse(clean_url).path.split('/')[1]
    when 'paypal.com'
      'paypal'
    else
      URI.parse(clean_url).path.sub(/\A\//, '')
    end
  rescue
    nil
  end

  def platform_name
    return 'GitHub Sponsors' if platform == 'github.com'
    platform.split('.').first
  end

  def full_name
    if approved?
    "#{name} (#{platform_name})"
    else
      platform
    end
  end

  def host
    return nil unless platform == 'opencollective.com'

    collective['host'] || name
  end

  def to_s
    name
  end

  def sync
    fetch_collective
    fetch_github_sponsors
    update(last_synced_at: Time.now)
  end

  def sync_async
    FundingSourceWorker.perform_async(id)
  end

  def self.sync_least_recently_synced
    FundingSource.where(last_synced_at: nil).or(FundingSource.where("last_synced_at < ?", 1.day.ago)).order('last_synced_at asc nulls first').limit(500).each do |funding_source|
      funding_source.sync_async
    end
  end

  def self.sync_all
    FundingSource.all.each do |project|
      project.sync_async
    end
  end

  def fetch_collective
    return unless platform == 'opencollective.com'

    oc_url = "https://opencollective.ecosyste.ms/api/v1/collectives/#{name}"
    response = ecosystems_api_request(oc_url)
    return unless response.success?
    self.collective = JSON.parse(response.body)
    self.save if changed?
  end

  def fetch_github_sponsors
    return unless platform == 'github.com'

    gh_url = "https://sponsors.ecosyste.ms/api/v1/accounts/#{name.downcase}"
    response = ecosystems_api_request(gh_url)
    return unless response.success?
    self.github_sponsors = JSON.parse(response.body)
    self.save if changed?
  rescue
    nil
  end

  def minimum_donation_ammount_cents
    return 100 unless platform == 'github.com'

    if github_sponsors['minimum_sponsorship_amount'].present?
      github_sponsors['minimum_sponsorship_amount'] * 100
    else
      100
    end
  end
end
