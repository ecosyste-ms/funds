class FundsController < ApplicationController
  def index
    @funds = Fund.all
    @pagy, @funds = pagy(@funds)
  end

  def show
    @fund = Fund.find_by(slug: params[:id])

    @allocation = @fund.allocations.order('created_at DESC').first
    @project_allocations = @allocation.project_allocations.includes(:project, :funding_source).order('amount_cents desc').where('amount_cents >= 1')
  end

  def transactions
    @fund = Fund.find_by(slug: params[:id])
    @transactions = @fund.transactions
    @pagy, @transactions = pagy(@transactions)
  end
end
