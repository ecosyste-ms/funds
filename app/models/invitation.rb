class Invitation < ApplicationRecord

  validates :token, presence: true, uniqueness: true

  belongs_to :project_allocation

  before_validation :generate_token, on: :create

  scope :accepted, -> { where.not(accepted_at: nil) }
  scope :rejected, -> { where.not(rejected_at: nil) }
  scope :pending, -> { where(accepted_at: nil, rejected_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :draft, -> { where(status: 'DRAFT') }

  def self.delete_expired
    Invitation.draft.not_deleted.find_each do |invitation|
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
    status == 'DRAFT' && Time.zone.now > decline_deadline
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
    SyncInviteWorker.perform_async(id)
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
      update!(data: response_body['data']['expense'], status: response_body['data']['expense']['status'])
    end
  end

  def edit_expense(amount)
    query = <<~GRAPHQL
      mutation($expense: ExpenseReferenceInput!, $input: ExpenseEditInput!) {
        editExpense(expense: $expense, input: $input) {
          id
          status
        }
      }
    GRAPHQL

    variables = {
      expense: {
        id: data['id']
      },
      input: {
        amount: amount
      }
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
      puts "Edited expense:"
      puts JSON.pretty_generate(response_body['data']['editExpense'])
    end
  end

  def delete_expense
    query = <<~GRAPHQL
      mutation($expense: ExpenseReferenceInput!) {
        deleteExpense(expense: $expense) {
          id
        }
      }
    GRAPHQL
  
    variables = {
      expense: { id: data['id'] }
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
      update!(status: 'DELETED', deleted_at: Time.zone.now)
    end
  end

  def approve_expense
    query = <<~GRAPHQL
      mutation($expense: ExpenseReferenceInput!, $action: ExpenseProcessAction!) {
        processExpense(expense: $expense, action: $action) {
          id
          status
        }
      }
    GRAPHQL

    variables = {
      expense: {
        id: data['id']
      },
      action: "APPROVE"
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
      puts "Approved expense:"
      puts JSON.pretty_generate(response_body['data']['processExpense'])
      update!(status: response_body['data']['processExpense']['status'])
    end
  end

  def unapprove_expense
    query = <<~GRAPHQL
      mutation($expense: ExpenseReferenceInput!, $action: ExpenseProcessAction!) {
        processExpense(expense: $expense, action: $action) {
          id
          status
        }
      }
    GRAPHQL

    variables = {
      expense: {
        id: data['id']
      },
      action: "UNAPPROVE"
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
      puts "Unapproved expense:"
      puts JSON.pretty_generate(response_body['data']['processExpense'])
      update!(status: response_body['data']['processExpense']['status'])
    end
  end 

  def status
    return 'DELETED' if deleted_at.present?
    return nil if data.blank?
    data['status']
  end

  def legacy_order_id
    return nil if data.blank?
    data['legacyId']
  end
end
