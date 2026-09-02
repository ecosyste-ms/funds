# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::V1::ApplicationController
      def index
        fund_slug = params[:fund_slug].to_s.strip
        return head :bad_request if fund_slug.blank? || fund_slug.length > 100

        page = params[:page].present? ? params[:page].to_i : 1
        return head :bad_request if page < 1 || page > 100_000

        limit = params[:limit].present? ? params[:limit].to_i : 20
        return head :bad_request if limit < 1 || limit > 1000

        @fund = Fund.find_by(slug: fund_slug)
        return head :not_found unless @fund

        @projects = @fund.funded_projects
                         .joins(:project_allocations)
                         .select('projects.*, SUM(project_allocations.amount_cents) AS total_amount_cents')
                         .group('projects.id')

        @projects = Project.from(@projects, :projects).order('total_amount_cents DESC').includes(:project_allocations)

        @pagy, @projects = pagy(@projects, page: page, limit: limit)
      end
    end
  end
end
