class FundingSource < ApplicationRecord
  validates :url, presence: true

  has_many :projects
  has_many :project_allocations

  scope :platform, ->(platform) { where(platform: platform) }

  APPROVED_PLATFORMS = ['opencollective.com', 'github.com', 'tidelift.com', 'patreon.com', 
  'liberapay.com', 'paypal.com', 'ko-fi.com', 'funding.communitybridge.org','buymeacoffee.com']

  def approved?
    APPROVED_PLATFORMS.include?(platform)
  end

  def name
    case platform
    when 'github.com'
      URI.parse(url).path.split('/')[2]
    when 'tidelift.com'
      URI.parse(url).path.split('/').last
    when 'opencollective.com'
      URI.parse(url).path.split('/')[1]
    when 'paypal.com'
      'paypal'
    else
      URI.parse(url).path.sub(/\A\//, '')
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
