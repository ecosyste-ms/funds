class FundingSource < ApplicationRecord
  validates :url, presence: true

  belongs_to :project
  has_many :project_allocations

  scope :platform, ->(platform) { where(platform: platform) }
end
