class Admin::InvitationsController < Admin::ApplicationController
  def index
    @invitations = Invitation
      .select('invitations.*, projects.url, projects.name as project_name, funds.name as fund_name, funds.slug as fund_slug')
      .joins(project_allocation: [:project, :fund])
      .includes(:project_allocation)
      

    if params[:sort] == "amount"
      @invitations = @invitations.order("project_allocation.amount_cents #{params[:order] || 'asc'}")
    elsif params[:sort] == "fund"
      @invitations = @invitations.order("funds.name #{params[:order] || 'asc'}")
    elsif params[:sort] == "status"
      @invitations = @invitations.sort_by do |i|
        [
          case
          when i.accepted_at.nil? && i.rejected_at.nil? # Pending
            params[:order] == "asc" ? 0 : 2
          when i.accepted_at.present? # Accepted
            1
          else # Rejected
            params[:order] == "asc" ? 2 : 0
          end,
          (i.accepted_at || i.rejected_at || Time.at(0)) # Sort by the most recent action timestamp
        ]
      end
    else
      @invitations = @invitations.order(created_at: :desc)
    end
  end
end