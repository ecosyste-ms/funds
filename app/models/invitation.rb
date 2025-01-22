class Invitation < ApplicationRecord

  validates :token, presence: true, uniqueness: true

  belongs_to :project_allocation

  before_validation :generate_token, on: :create

  def self.delete_expired
    Invitation.all.find_each do |invitation|
      invitation.delete_expense if invitation.expired?
    end
  end

  def project
    project_allocation.project
  end

  def generate_token
    loop do
      self.token = SecureRandom.hex(16)
      break unless Invitation.exists?(token: token)
    end
  end

  def fund
    project_allocation.fund
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
      token,
      decline_deadline.strftime("%B %d, %Y"),
      fund
    ).deliver_now
  end

  def send_expense_invite_email
    return if draft_key.blank?
    MaintainerMailer.expense_email(
      self,
      email,
      project_allocation.project.to_s,
      project_allocation.funder_names,
      "$#{project_allocation.amount_cents / 100.0}",
      token,
      decline_deadline.strftime("%B %d, %Y"),
      fund
    ).deliver_now
  end

  def draft_key
    data['draftKey']
  end

  def html_url
    "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{project_allocation.fund.oc_project_slug}/expenses/#{member_invitation_id}"
  end

  def invite_url
    "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/expenses/#{member_invitation_id}?key=#{draft_key}"
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
          draft
          lockedFields
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
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error: #{response_body['errors']}"
    else
      puts "Expense details:"
      puts JSON.pretty_generate(response_body['data']['expense'])
      update!(data: response_body['data']['expense'])
    end
  end

  def delete_expense
    query = <<~GRAPHQL
      mutation($id: String!) {
        deleteExpense(id: $id) {
          id
        }
      }
    GRAPHQL

    variables = {
      id: member_invitation_id
    }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error: #{response_body['errors']}"
    else
      puts "Deleted expense:"
      puts JSON.pretty_generate(response_body['data']['deleteExpense'])
    end
  end
end
