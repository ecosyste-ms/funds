class ProjectAllocation < ApplicationRecord
  belongs_to :project
  belongs_to :allocation
  belongs_to :fund
  belongs_to :funding_source
end
