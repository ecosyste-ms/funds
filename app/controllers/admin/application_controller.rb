class Admin::ApplicationController < ApplicationController
  http_basic_authenticate_with name: ENV["SIDEKIQ_USERNAME"], password: ENV["SIDEKIQ_PASSWORD"] if Rails.env.production?
end