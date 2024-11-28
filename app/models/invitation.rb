class Invitation < ApplicationRecord

  validates :token, presence: true, uniqueness: true

  belongs_to :project_allocation

  before_validation :generate_token, on: :create

  def generate_token
    loop do
      self.token = SecureRandom.hex(16)
      break unless Invitation.exists?(token: token)
    end
  end

  def decline_deadline
    project_allocation.decline_deadline
  end

  def expired?
    Time.zone.now > decline_deadline
  end

  def accept!
    return if expired?
    update!(accepted_at: Time.zone.now, rejected_at: nil)
    project_allocation.accept_funding!
  end

  def reject!
    return if expired?
    update!(rejected_at: Time.zone.now, accepted_at: nil)
    project_allocation.reject_funding!
  end

  def accepted?
    accepted_at.present?
  end

  def rejected?
    rejected_at.present?
  end

  def send_email
    MaintainerMailer.invitation_email(
      email,
      project_allocation.project.to_s,
      project_allocation.funder_names,
      "$#{project_allocation.amount_cents / 100.0}",
      "https://example.com/invite",
      decline_deadline.strftime("%B %d, %Y")
    ).deliver_now
  end

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
