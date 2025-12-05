class Invitation < ApplicationRecord
  validates :token, presence: true, uniqueness: true

  belongs_to :project_allocation
  has_many :events, class_name: 'ProjectAllocationEvent'

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
    log_event('invitation_email_sent', metadata: { email: email })
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
    log_event('expense_email_sent', metadata: { email: email })
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
    start_time = Time.current

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    duration_ms = ((Time.current - start_time) * 1000).round
    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error: #{response_body['errors']}"
      log_event('expense_sync_failed', status: 'error',
        message: response_body['errors'].map { |e| e['message'] }.join(', '),
        metadata: { duration_ms: duration_ms, errors: response_body['errors'] })
    else
      puts "Expense details:"
      puts JSON.pretty_generate(response_body['data']['expense'])
      old_status = read_attribute(:status)
      new_status = response_body['data']['expense']['status']
      update!(data: response_body['data']['expense'], status: new_status)
      log_event('expense_synced', metadata: { duration_ms: duration_ms, old_status: old_status, new_status: new_status })
    end
  rescue Faraday::Error => e
    log_event('expense_sync_failed', status: 'error',
      message: "Network error: #{e.message}",
      metadata: { error_class: e.class.name })
  end

  def edit_expense(amount)
    query = <<~GRAPHQL
      mutation($expense: ExpenseUpdateInput!) {
        editExpense(expense: $expense) {
          id
          status
        }
      }
    GRAPHQL

    variables = {
      expense: {
        id: data['id'],
        items: [
          {
            amountV2: {
              valueInCents: amount,
              currency: 'USD'
            }
          }
        ]
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
    start_time = Time.current

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    duration_ms = ((Time.current - start_time) * 1000).round
    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error: #{response_body['errors']}"
      log_event('expense_deleted', status: 'error',
        message: response_body['errors'].map { |e| e['message'] }.join(', '),
        metadata: { duration_ms: duration_ms, errors: response_body['errors'] })
    else
      puts "Deleted expense:"
      puts JSON.pretty_generate(response_body['data']['deleteExpense'])
      update!(status: 'DELETED', deleted_at: Time.zone.now)
      log_event('expense_deleted', metadata: { duration_ms: duration_ms })
    end
  rescue Faraday::Error => e
    log_event('expense_deleted', status: 'error',
      message: "Network error: #{e.message}",
      metadata: { error_class: e.class.name })
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
    start_time = Time.current

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    duration_ms = ((Time.current - start_time) * 1000).round
    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error: #{response_body['errors']}"
      log_event('expense_approved', status: 'error',
        message: response_body['errors'].map { |e| e['message'] }.join(', '),
        metadata: { duration_ms: duration_ms, errors: response_body['errors'] })
    else
      puts "Approved expense:"
      puts JSON.pretty_generate(response_body['data']['processExpense'])
      new_status = response_body['data']['processExpense']['status']
      update!(status: new_status)
      log_event('expense_approved', metadata: { duration_ms: duration_ms, new_status: new_status })
    end
  rescue Faraday::Error => e
    log_event('expense_approved', status: 'error',
      message: "Network error: #{e.message}",
      metadata: { error_class: e.class.name })
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
    start_time = Time.current

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    duration_ms = ((Time.current - start_time) * 1000).round
    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error: #{response_body['errors']}"
      log_event('expense_unapproved', status: 'error',
        message: response_body['errors'].map { |e| e['message'] }.join(', '),
        metadata: { duration_ms: duration_ms, errors: response_body['errors'] })
    else
      puts "Unapproved expense:"
      puts JSON.pretty_generate(response_body['data']['processExpense'])
      new_status = response_body['data']['processExpense']['status']
      update!(status: new_status)
      log_event('expense_unapproved', metadata: { duration_ms: duration_ms, new_status: new_status })
    end
  rescue Faraday::Error => e
    log_event('expense_unapproved', status: 'error',
      message: "Network error: #{e.message}",
      metadata: { error_class: e.class.name })
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

  def log_event(event_type, status: 'success', message: nil, metadata: {})
    ProjectAllocationEvent.create!(
      project_allocation: project_allocation,
      fund_id: project_allocation.fund_id,
      allocation_id: project_allocation.allocation_id,
      invitation: self,
      event_type: event_type,
      status: status,
      message: message,
      metadata: metadata
    )
  end
end
