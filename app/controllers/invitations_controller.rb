class InvitationsController < ApplicationController

  def show
    @invitation = Invitation.find_by_token(params[:token])
  end

  def accept
    @invitation = Invitation.find_by_token(params[:token])
    invitation.accept!
    redirect_to invitation_path(@invitation.token)
  end

  def reject
    @invitation = Invitation.find_by_token(params[:token])
    invitation.reject!
    redirect_to invitation_path(@invitation.token)
  end
end