class FundsController < ApplicationController
  def index
    @funds = Fund.all
    @pagy, @funds = pagy(@funds)
  end

  def show
    @fund = Fund.find_by(slug: params[:id])

    @allocations = @fund.allocations.displayable
    @pagy, @allocations = pagy(@allocations)
    
    @projects = @fund.projects
    @project_pagy, @projects = pagy(@projects)

    @transactions = @fund.transactions
    @transactions_pagy, @transactions = pagy(@transactions)
  end

  def transactions
    @fund = Fund.find_by(slug: params[:id])
    @transactions = @fund.transactions
    @pagy, @transactions = pagy(@transactions)
  end
end
