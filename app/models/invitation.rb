class Invitation < ApplicationRecord
  belongs_to :project_allocation

  def html_url
    "https://staging.opencollective.com/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{project_allocation.fund.oc_project_slug}/expenses/#{member_invitation_id}"
  end

  def sync_async
    SyncInvitationWorker.perform_async(id)
  end

  def sync
    query = <<~GRAPHQL
      query($id: String!) {
        expense(id: $id) {
          id
          legacyId
          status
          description
          amount
          currency
          payee {
            ... on Individual {
              id
              name
              email
            }
            ... on Organization {
              id
              name
            }
          }
          account {
            id
            slug
          }
        }
      }
    GRAPHQL

    variables = {
      id: member_invitation_id
    }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    response_body = JSON.parse(response.body)

    # Check for errors or print the result
    if response_body['errors']
      puts "Error: #{response_body['errors']}"
    else
      puts "Expense details:"
      puts JSON.pretty_generate(response_body['data']['expense'])
      update!(data: response_body['data']['expense'])
    end
  end
end
