class FundingSourcesController < ApplicationController
  def index
    @funding_sources = FundingSource.all
    @pagy, @funding_sources = pagy(@funding_sources)
  end

  def show
    @funding_source = FundingSource.find(params[:id])
    @projects = @funding_source.projects
    @pagy, @projects = pagy(@projects)

    @project_allocations = @funding_source.project_allocations
    @project_allocations_pagy, @project_allocations = pagy(@project_allocations)
  end
end