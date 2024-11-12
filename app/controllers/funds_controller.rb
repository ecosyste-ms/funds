class FundsController < ApplicationController
  def index
    @featured_funds = Fund.featured.limit(4)
    @funds = Fund.not_featured.order('random()').limit(12)
  end

  def show
    @fund = Fund.find_by(slug: params[:id])

    @allocation = @fund.allocations.order('created_at DESC').first
    if @allocation
      @project_allocations = @allocation.project_allocations.includes(:project, :funding_source).order('amount_cents desc').where('amount_cents >= 1')
    end
  end

  def transactions
    @fund = Fund.find_by(slug: params[:id])
    @transactions = @fund.transactions
    @pagy, @transactions = pagy(@transactions)
  end
end
