class FundingSourcesController < ApplicationController
  def index
    @funding_sources = FundingSource.all
  end
end