class Admin::InvitationsController < Admin::ApplicationController
  def index
    @invitations = Invitation
      .select('invitations.*, projects.url, projects.name as project_name, funds.name as fund_name, funds.slug as fund_slug')
      .joins(project_allocation: [:project, :fund])
      .order(created_at: :desc)
  end
end