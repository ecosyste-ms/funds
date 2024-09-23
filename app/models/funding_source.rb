class FundingSource < ApplicationRecord
  validates :url, presence: true

  has_many :projects
  has_many :project_allocations

  scope :platform, ->(platform) { where(platform: platform) }

  def name
    case platform
    when 'github.com'
      URI.parse(url).path.split('/')[2]
    when 'tidelift.com'
      URI.parse(url).path.split('/').last
    else
      URI.parse(url).path.sub(/\A\//, '')
    end
  end

  def to_s
    name
  end
end
