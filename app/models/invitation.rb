class Invitation < ApplicationRecord
  belongs_to :project_allocation
  belongs_to :fund, through: :project_allocation
  belongs_to :project, through: :project_allocation
  belongs_to :allocation, through: :project_allocation

  def html_url
    "https://staging.opencollective.com/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{fund.oc_project_slug}/expenses/#{member_invitation_id}"
  end
end
