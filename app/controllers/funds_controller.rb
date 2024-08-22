class FundsController < ApplicationController
  def index
    @funds = Fund.all
    @pagy, @funds = pagy(@funds)
  end

  def show
    @fund = Fund.find_by(slug: params[:id])
    @allocations = @fund.allocations
    @pagy, @allocations = pagy(@allocations)
  end
end
