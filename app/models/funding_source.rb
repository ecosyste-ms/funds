class FundingSource < ApplicationRecord
  validates :url, presence: true

  has_many :projects
  has_many :project_allocations

  APPROVED_PLATFORMS = ['opencollective.com', 'github.com', 'patreon.com', 
  'liberapay.com', 'ko-fi.com', 'funding.communitybridge.org', 'buymeacoffee.com', 'paypal.com']
  
  scope :platform, ->(platform) { where(platform: platform) }
  scope :approved, -> { where(platform: APPROVED_PLATFORMS) }
  
  def self.open_collective_github_sponsors_mapping
    @open_collective_github_sponsors_mapping ||= begin
      url = 'https://raw.githubusercontent.com/opencollective/opencollective-tools/refs/heads/main/github-sponsors/csv-import-mapping.json'
      response = Faraday.get(url)
      JSON.parse(response.body)
    rescue
      {}
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
    url.strip.chomp.gsub(/\[|\]/, '') # remove square brackets for vllm project with invalid funding.yml
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
    return nill unless platform == 'opencollective.com'

    collective['host'] || name
  end

  def to_s
    name
  end

  def sync
    fetch_collective
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

    conn = Faraday.new(url: oc_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    response = conn.get
    return unless response.success?
    self.collective = JSON.parse(response.body)
    self.save
  end
end
