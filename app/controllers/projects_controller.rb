class ProjectsController < ApplicationController
  def index
    @fund = Fund.find_by!(slug: params[:fund_id])
    raise ActiveRecord::RecordNotFound unless @fund
    @projects = @fund.funded_projects_with_totals
    @pagy, @projects = pagy(@projects)
  end

  def show
    @project = Project.find(params[:id])
    @project_allocations = @project.project_allocations
      .includes(:fund, :allocation, :invitation, :funding_source)
      .order('allocations.created_at DESC')
  end
end
