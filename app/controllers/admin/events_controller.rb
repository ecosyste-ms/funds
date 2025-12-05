class Admin::EventsController < Admin::ApplicationController
  def index
    @events = ProjectAllocationEvent.includes(:project_allocation, :fund, :allocation, :invitation, project_allocation: :project)
    @events = @events.for_fund(Fund.find(params[:fund_id])) if params[:fund_id].present?
    @events = @events.for_allocation(Allocation.find(params[:allocation_id])) if params[:allocation_id].present?
    @events = @events.for_type(params[:event_type]) if params[:event_type].present?
    @events = @events.where(status: params[:status]) if params[:status].present?
    @events = @events.recent

    @pagy, @events = pagy(@events, limit: 50)

    @funds = Fund.order(:name)
    @allocations = Allocation.includes(:fund).order(created_at: :desc).limit(50)
  end
end
