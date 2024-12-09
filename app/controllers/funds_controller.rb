class FundsController < ApplicationController
  def index
    @featured_funds = Fund.featured.limit(4)
    @funds = Fund.not_featured.short_names.order(Arel.sql('CASE WHEN projects_count > 0 THEN 0 ELSE 1 END, RANDOM()')).limit(12)
  end

  def show
    @fund = Fund.find_by(slug: params[:id])
    raise ActiveRecord::RecordNotFound unless @fund

    @allocation = @fund.allocations.order('created_at DESC').first
    if @allocation
      @project_allocations = @allocation.project_allocations.includes(:project, :funding_source, :invitation).order('amount_cents desc').where('amount_cents >= 1')
    end
  end

  def transactions
    @fund = Fund.find_by(slug: params[:id])
    @transactions = @fund.transactions
    @pagy, @transactions = pagy(@transactions)
  end
end
