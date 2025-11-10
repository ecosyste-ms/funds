class InvitationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:accept, :reject]

  def show
    if Rails.env.development? && params[:token].blank?
      # make a new invitation for development
      @invitation = Invitation.create!(email: 'test@test.com', project_allocation: ProjectAllocation.first)
      redirect_to invitation_path(token: @invitation.token) and return
    end
    @invitation = Invitation.find_by_token(params[:token])
    raise ActiveRecord::RecordNotFound unless @invitation
    @project_allocation = @invitation.project_allocation
    @project = @project_allocation.project
    raise ActiveRecord::RecordNotFound unless @invitation
  end

  def accept
    @invitation = Invitation.find_by_token(params[:token])
    raise ActiveRecord::RecordNotFound unless @invitation
    @invitation.accept!
    redirect_to invitation_path(token: @invitation.token)
  end

  def reject
    @invitation = Invitation.find_by_token(params[:token])
    raise ActiveRecord::RecordNotFound unless @invitation
    @invitation.reject!
    redirect_to invitation_path(token: @invitation.token)
  end
end