class InvitationsController < ApplicationController

  def show
    @invitation = Invitation.find_by_token(params[:token])
  end

  def accept
    # find invitation by token
    # invitation.accept
    # redirect to invitation.html_url
  end

  def reject
    # find invitation by token
    # invitation.reject
    # redirect back invitation.html_url
  end
end