module EcosystemsApiClient
  extend ActiveSupport::Concern

  included do
    def self.ecosystems_api_request(url, params = {})
      conn = Faraday.new(url: url) do |faraday|
        faraday.headers['User-Agent'] = 'funds.ecosyste.ms'
        faraday.headers['X-API-Key'] = ENV['ECOSYSTEMS_API_KEY'] if ENV['ECOSYSTEMS_API_KEY']
        faraday.response :follow_redirects
        faraday.adapter Faraday.default_adapter
      end
      
      response = conn.get do |req|
        req.params = params unless params.empty?
      end
      
      response
    end

    def ecosystems_api_request(url, params = {})
      self.class.ecosystems_api_request(url, params)
    end
  end
end