class AllocationsController < ApplicationController
  def show
    @fund = Fund.find_by(slug: params[:fund_id])
    @allocation = @fund.allocations.find(params[:id])
    @project_allocations = @allocation.project_allocations.includes(:project).order('amount_cents desc').where('amount_cents >= 1')
  end
end
