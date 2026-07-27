module Api
  module V1
    class FundsController < Api::V1::ApplicationController
      def search
        query = params[:query].to_s.strip
        return head :bad_request if query.blank? || query.length > 100

        page = params[:page].present? ? params[:page].to_i : nil
        return head :bad_request if page && page < 1

        @funds = Fund.search(query)
        @pagy, @funds = pagy(@funds, page: page)

        render :search, formats: :json
      end

      def show
        slug = params[:slug].to_s.strip
        return head :bad_request if slug.blank? || slug.length > 100

        @fund = Fund.find_by(slug: slug)
        return head :not_found unless @fund

        render :show, formats: :json
      end
    end
  end
end
