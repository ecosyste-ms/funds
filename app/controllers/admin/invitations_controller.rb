class Admin::InvitationsController < Admin::ApplicationController
  def index
    dates = Invitation.group_by_month(:created_at, reverse: true).count
    @dates = dates.map { |date, count| [date, count] }.to_h

    if params[:month] && params[:year]
      month = params[:month].to_i
      year = params[:year].to_i
      @selected_date = Time.zone.local(year, month)
    else
      month = @dates.keys.first.month
      year = @dates.keys.first.year
      @selected_date = Time.zone.local(year, month)
    end
  
    scope = Invitation.where(created_at: Time.zone.local(year, month)..Time.zone.local(year, month).end_of_month)

    @invitations = scope
      .select('invitations.*, projects.url, projects.name as project_name, funds.name as fund_name, funds.slug as fund_slug')
      .joins(project_allocation: [:project, :fund])
      .includes(project_allocation: [:project, :fund])

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