class Admin::ApplicationController < ApplicationController
  before_action :require_basic_auth, if: -> { Rails.env.production? }

  private

  def require_basic_auth
    authenticate_or_request_with_http_basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV["SIDEKIQ_USERNAME"]) &&
        ActiveSupport::SecurityUtils.secure_compare(password, ENV["SIDEKIQ_PASSWORD"])
    end
  end
end