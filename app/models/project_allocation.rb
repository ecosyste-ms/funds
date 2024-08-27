class ProjectAllocation < ApplicationRecord
  belongs_to :project
  belongs_to :allocation
  belongs_to :fund
  belongs_to :funding_source, optional: true

  scope :with_funding_source, -> { where.not(funding_source_id: nil) }
end
