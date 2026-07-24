module Api
  module V1
    class FundsController < ApplicationController
      def search
          return head :bad_request if params[:query].blank?

          funds = Fund.search(params[:query])

          return head :not_found if funds.empty?

          render json: {
            funds: funds.map do |fund|
              {
                name: fund.name,
                url: fund_url(fund),
                description: fund.description,
                total_funded_projects: fund.total_funded_projects,
                total_donors: fund.total_donors
              }
            end
          }
      end

      def show
        fund = Fund.find_by(slug: params[:id])

        return head :not_found unless fund

        render json: {
          projects_count: fund.projects.count,
          project_downloads: fund.funded_project_downloads,
          project_dependent_repos: fund.funded_project_dependent_repos,
          project_dependent_packages: fund.funded_project_dependent_packages,

          total_donation_amount: {
            value: fund.total_donation_amount,
            currency: "USD"
          },

          total_donors: fund.total_donors,

          funded_projects_count: fund.funded_projects_count,

          completed_allocations_count: fund.allocations.completed.count,

          completed_allocations_total: {
            value: fund.completed_allocations_total,
            currency: "USD"
          },

          top_3_funders: fund.funders.first(3).map do |funder|
            {
              funder_name: funder[:name],
              funder_amount: {
                value: funder[:amount],
                currency: "USD"
              },
              funder_link: "https://opencollective.com/#{funder[:slug]}"
            }
          end
        }
      end

      private

      def fund_url(fund)
        Rails.application.routes.url_helpers.fund_url(
          fund,
          host: ENV.fetch("APP_HOST", "funds.ecosyste.ms")
        )
      end
    end
  end
end