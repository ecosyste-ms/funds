ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require 'webmock/minitest'
require 'mocha/minitest'

require 'sidekiq_unique_jobs/testing'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  def record_select_queries
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s.lstrip
      queries << sql if (sql.start_with?('SELECT') || sql.start_with?('WITH')) && !payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { yield }
    queries
  end

  Shoulda::Matchers.configure do |config|
    config.integrate do |with|
      with.test_framework :minitest
      with.library :rails
    end
  end
end
