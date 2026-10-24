require 'test_helper'

class ApiDocumentationTest < ActionDispatch::IntegrationTest
  test 'serves the OpenAPI document with timestamp examples as strings' do
    get '/docs/api/v1/openapi.yaml'

    assert_response :success
    document = YAML.safe_load(response.body)
    invitation = document.fetch('components').fetch('schemas').fetch('FundingInvitation')
    %w[invitation_accepted_at invitation_rejected_at].each do |property|
      assert_equal '2026-10-14T23:59:59+00:00', invitation.fetch('properties').fetch(property).fetch('example')
    end
  end
end
