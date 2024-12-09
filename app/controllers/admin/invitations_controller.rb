class Admin::InvitationsController < Admin::ApplicationController
  def index
    @invitations = Invitation.all.includes({ project_allocation: :project }).order(created_at: :desc)
  end
end