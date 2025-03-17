class ProjectsController < ApplicationController
  def index
    @fund = Fund.find_by!(slug: params[:fund_id])
    raise ActiveRecord::RecordNotFound unless @fund
    @projects = @fund.funded_projects
        .joins(:project_allocations)
        .select('projects.*, SUM(project_allocations.amount_cents) AS total_amount_cents')
        .group('projects.id')

    @projects = Project.from(@projects, :projects).order('total_amount_cents DESC').includes(:project_allocations)

    @pagy, @projects = pagy(@projects)
  end

  def show
    @project = Project.find(params[:id])
  end
end