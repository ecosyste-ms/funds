class FundsController < ApplicationController
  def index
    @featured_funds = Fund.featured.limit(4)
    @funds = Fund.not_featured.short_names.order(Arel.sql('CASE WHEN projects_count > 0 THEN 0 ELSE 1 END, RANDOM()')).limit(12)
  end

  def search
    @funds = Fund.search(params[:query])
    @pagy, @funds = pagy(@funds)
  end

  def show
    @fund = Fund.find_by!(slug: params[:id])
    raise ActiveRecord::RecordNotFound unless @fund

    @allocation = @fund.allocations.order('created_at DESC').first
    if @allocation
      @project_allocations = @allocation.project_allocations.includes(:funding_source, :invitation)
                                                             .order('amount_cents desc, score desc')
                                                             .where('amount_cents >= 1')
                                                             .joins(:project)
                                                             .select('project_allocations.*, projects.name as project_name, projects.url as project_url, projects.total_downloads as project_downloads, projects.total_dependent_repos as project_dependent_repos, projects.total_dependent_packages as project_dependent_packages, projects.funding_rejected as project_funding_rejected')
    end
  end

  def setup
    @fund = Fund.find_by!(slug: params[:id])
    raise ActiveRecord::RecordNotFound unless @fund

    @fund.setup_opencollective_project
    raise ActiveRecord::RecordNotFound unless @fund.oc_project_slug
    redirect_to donate_fund_path(@fund)
  end

  def donate
    @fund = Fund.find_by!(slug: params[:id])
    raise ActiveRecord::RecordNotFound unless @fund

    @allocation = @fund.allocations.order('created_at DESC').first

    if params[:OrderId].present?
      id = params[:OrderId]

      @transaction = Transaction.donations.where("transactions.order->>'legacyId' = ?", id.to_s).first
      if @transaction.nil?
        @fund.sync_transactions
        @transaction = Transaction.donations.where("transactions.order->>'legacyId' = ?", id.to_s).first
        raise ActiveRecord::RecordNotFound unless @transaction
      end
    end
  end

  def transactions
    @fund = Fund.find_by!(slug: params[:id])
    @transactions = @fund.transactions
    @pagy, @transactions = pagy(@transactions)
  end


  def funders
    @fund = Fund.find_by!(slug: params[:id])
    @funders = @fund.funders
  end
end
