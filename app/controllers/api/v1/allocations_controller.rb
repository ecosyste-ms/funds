# frozen_string_literal: true

module Api
  module V1
    class AllocationsController < Api::V1::ApplicationController
      def index
        month_year = params[:month_year].to_s.strip
        return head :bad_request if month_year.blank? || month_year.length > 100

        fund_slug = params[:fund_slug].to_s.strip
        return head :bad_request if fund_slug.blank? || fund_slug.length > 100

        @fund = Fund.find_by(slug: fund_slug)
        return head :not_found unless @fund

        @allocation = @fund.allocations.find_by(slug: month_year)
        return head :not_found unless @allocation

        @project_allocations = @allocation.project_allocations.includes(:funding_source, :invitation)
                                          .order('amount_cents desc, score desc')
                                          .where('amount_cents >= 1')
                                          .joins(:project)
                                          .includes(:project, :funding_source)
                                          .select(
                                            'project_allocations.*, ' \
                                            'projects.name as project_name, ' \
                                            'projects.url as project_url, ' \
                                            'projects.total_downloads as project_downloads, ' \
                                            'projects.total_dependent_repos as project_dependent_repos, ' \
                                            'projects.total_dependent_packages as project_dependent_packages, ' \
                                            'projects.funding_rejected as project_funding_rejected'
                                          ).reject { |pa| pa.project_url.nil? || @allocation.completed? && !pa.success? }
      end
    end
  end
end
