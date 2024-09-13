class ProjectsController < ApplicationController
  def index
    @fund = Fund.find_by(slug: params[:fund_id])
    @projects = @fund.possible_projects
    @pagy, @projects = pagy(@projects)
  end

  def show
    @project = Project.find(params[:id])
  end
end