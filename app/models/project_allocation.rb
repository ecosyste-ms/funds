class ProjectAllocation < ApplicationRecord
  belongs_to :project
  belongs_to :allocation
  belongs_to :fund
  belongs_to :funding_source, optional: true

  scope :with_funding_source, -> { where.not(funding_source_id: nil) }

  scope :platform, ->(platform) { joins(:funding_source).where(funding_sources: { platform: platform }) }

  def create_expense_invite
    # send email to project owner to invite them to create an expense
    # inviteMember mutation in opencollective graphql api
  end
end
