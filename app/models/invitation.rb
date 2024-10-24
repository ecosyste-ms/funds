class Invitation < ApplicationRecord
  belongs_to :project_allocation

  def html_url
    "https://staging.opencollective.com/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{project_allocation.fund.oc_project_slug}/expenses/#{member_invitation_id}"
  end
end
