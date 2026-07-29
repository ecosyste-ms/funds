# frozen_string_literal: true

module Api
  module V1
    class FundsController < Api::V1::ApplicationController
      def search
        query = params[:query].to_s.strip
        return head :bad_request if query.blank? || query.length > 100

        page = params[:page].present? ? params[:page].to_i : 1
        return head :bad_request if page < 1 || page > 100_000

        limit = params[:limit].present? ? params[:limit].to_i : 20
        return head :bad_request if limit < 1 || limit > 1000

        @funds = Fund.search(query)
        @pagy, @funds = pagy(@funds, page: page, limit: limit)

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
