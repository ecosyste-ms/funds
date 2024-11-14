require 'sidekiq'
require 'sidekiq-status'

Sidekiq.configure_server do |config|
  config.redis = { ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end

  SidekiqUniqueJobs::Server.configure(config)

  Sidekiq::Status.configure_server_middleware config, expiration: 60.minutes.to_i
end

Sidekiq.configure_client do |config|
  config.logger = Rails.logger if Rails.env.test?
  # accepts :expiration (optional)
  Sidekiq::Status.configure_client_middleware config, expiration: 60.minutes.to_i

  config.redis = { ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end
end