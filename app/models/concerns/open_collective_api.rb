module OpenCollectiveApi
  extend ActiveSupport::Concern

  included do
    def oc_api_request(query:, variables:, event_type:)
      start_time = Time.current

      response = Faraday.post(
        "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
        { query: query, variables: variables }.to_json,
        { 'Content-Type' => 'application/json' }
      )

      duration_ms = ((Time.current - start_time) * 1000).round
      response_body = JSON.parse(response.body)

      if response_body['errors']
        log_event(event_type,
          status: 'error',
          message: response_body['errors'].map { |e| e['message'] }.join(', '),
          metadata: {
            duration_ms: duration_ms,
            errors: response_body['errors'],
            variables: variables
          }
        )
        nil
      else
        log_event(event_type,
          status: 'success',
          metadata: {
            duration_ms: duration_ms,
            response: response_body['data']
          }
        )
        response_body
      end
    rescue Faraday::Error => e
      log_event(event_type,
        status: 'error',
        message: "Network error: #{e.message}",
        metadata: { error_class: e.class.name, variables: variables }
      )
      nil
    rescue JSON::ParserError => e
      log_event(event_type,
        status: 'error',
        message: "Invalid JSON response: #{e.message}",
        metadata: { error_class: e.class.name, response_body: response&.body&.truncate(1000) }
      )
      nil
    end
  end
end
