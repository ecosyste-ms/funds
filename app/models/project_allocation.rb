class ProjectAllocation < ApplicationRecord
  include OpenCollectiveApi

  belongs_to :project
  belongs_to :allocation
  belongs_to :fund
  belongs_to :funding_source, optional: true
  has_one :invitation
  has_many :events, class_name: 'ProjectAllocationEvent'

  scope :with_funding_source, -> { where.not(funding_source_id: nil) }
  scope :with_approved_funding_source, -> { joins(:funding_source).where(funding_sources: { platform: FundingSource::APPROVED_PLATFORMS }) }
  scope :without_funding_source, -> { where(funding_source_id: nil) }
  
  scope :paid, -> { where.not(paid_at: nil) }
  scope :unpaid, -> { where(paid_at: nil) }

  scope :platform, ->(platform) { joins(:funding_source).where(funding_sources: { platform: platform }) }
  scope :not_platform, ->(platform) { joins(:funding_source).where.not(funding_sources: { platform: platform }) }

  scope :funding_not_rejected, -> { joins(:project).where(projects: { funding_rejected: false }) }

  scope :expense_invites, -> { without_funding_source.funding_not_rejected }
  scope :proxy_collectives, -> { with_approved_funding_source.funding_not_rejected.not_platform('opencollective.com') }

  def self.update_funding_sources
    ProjectAllocation.without_funding_source.find_each(&:update_funding_source)
  end

  def update_funding_source
    return if Time.now > allocation_payout_date
    return if project.funding_rejected?
    if project.funding_source && project.funding_source.approved?
      self.funding_source_id = project.funding_source_id
    else
      self.funding_source_id = nil
    end
    save if changed?
  end

  def approved_funding_source?
    funding_source && funding_source.approved?
  end

  def minimum_funding_source_amount_met?
    funding_source && funding_source.minimum_donation_ammount_cents <= amount_cents
  end

  def is_osc_collective?
    funding_source && funding_source.platform == 'opencollective.com' && funding_source.host == 'opensource'
  end

  def is_non_osc_collective?
    funding_source && funding_source.platform == 'opencollective.com' && funding_source.host != 'opensource'
  end

  def is_proxy_collective?
    funding_source && funding_source.approved? && funding_source.platform != 'opencollective.com'
  end

  def is_invited?
    invitation.present?
  end

  def collective_slug
    funding_source.platform == 'opencollective.com' ? funding_source.name : nil
  end

  def payout_method_name
    return "Funding Rejected" if funding_rejected?

    if is_osc_collective?
      "Open Source Collective: #{funding_source.name}"
    elsif is_non_osc_collective?
      "Open Collective (non-OSC): #{funding_source.name} (#{funding_source.host})"
    elsif approved_funding_source?
      funding_source.url
    elsif project && project.contact_email.present?
      "Email invite: #{project.contact_email}"
    else
      "No valid payout method"
    end
  end

  def paid?
    paid_at.present?
  end

  def payout
    return if funding_rejected?
    return if paid?

    log_event('payout_started', metadata: { payout_method: payout_method_name, amount_cents: amount_cents })

    if is_osc_collective?
      puts "  Sending to OSC collective: #{funding_source.name}"
      result = send_to_osc_collective(collective_slug, amount_cents)
      if result
        update!(paid_at: Time.now)
        log_event('payout_completed', message: "Sent to OSC collective: #{funding_source.name}")
      else
        log_event('payout_failed', status: 'error', message: "Failed to send to OSC collective: #{funding_source.name}")
      end
    elsif is_non_osc_collective?
      puts "  Sending to non-OSC collective: #{funding_source.name}"
      result = send_draft_expense_invitation_to_collective(collective_slug, amount_cents, non_osc_collective_expense_invite_description)
      if result
        update!(paid_at: Time.now)
        log_event('payout_completed', message: "Sent to non-OSC collective: #{funding_source.name}")
      else
        log_event('payout_failed', status: 'error', message: "Failed to send to non-OSC collective: #{funding_source.name}")
      end
    elsif approved_funding_source? && minimum_funding_source_amount_met?
      puts "  Sending to approved funding source: #{funding_source.url}"
      proxy_collective = find_or_create_proxy_collective(funding_source.url)
      proxy_collective.set_payout_method
      if proxy_collective
        puts "  Adding funds to proxy collective: #{proxy_collective.slug}"
        expense = send_expense_to_vendor(proxy_collective, amount_cents)
        if expense
          expense.approve_expense
          update!(paid_at: Time.now)
          log_event('payout_completed', message: "Sent via proxy collective: #{proxy_collective.slug}")
        else
          log_event('payout_failed', status: 'error', message: "Failed to create expense for proxy collective: #{proxy_collective.slug}")
        end
      else
        log_event('payout_failed', status: 'error', message: "Failed to create proxy collective for: #{funding_source.url}")
      end
    elsif approved_funding_source? && !minimum_funding_source_amount_met?
      puts "  Skipping: amount below funding source minimum for #{funding_source.url}"
      log_event('payout_skipped', status: 'success', message: "Amount below funding source minimum", metadata: {
        funding_source_url: funding_source.url,
        amount_cents: amount_cents,
        minimum_cents: funding_source.minimum_donation_ammount_cents
      })
    elsif project && project.contact_email.present?
      puts "  Sending expense invite: #{project.contact_email}"
      result = send_expense_invite
      if result.is_a?(Hash) && result[:skipped]
        log_event('payout_skipped', status: 'success', message: "Skipped expense invite: #{result[:skipped]}", metadata: result)
      elsif result
        update!(paid_at: Time.now)
        log_event('payout_completed', message: "Sent expense invite to: #{project.contact_email}")
      else
        log_event('payout_failed', status: 'error', message: "Failed to send expense invite to: #{project.contact_email}")
      end
    else
      puts "  No valid payout method found for #{project.to_s}"
      log_event('payout_skipped', status: 'error', message: "No valid payout method found")
    end
  end

  def proxy_collective_expense_invite_description(proxy_collective)
    "Ecosystem allocation for #{project.to_s} on #{proxy_collective.website} from #{fund.name}"
  end

  def non_osc_collective_expense_invite_description
    <<~DESCRIPTION
      You are receiving this message because we are offering a donation for your work within the #{fund.name} open source ecosystem. A technical limitation with the Open Collective platform requires that we make donations like this (i.e. between legal entities) using the expense workflow.
  
      To complete the donation we need some further information from you. Please complete the following form in order for our team to process your payment promptly.
  
      For more information, please visit our FAQ at https://funds.ecosyste.ms/faq.

      If you have any questions or need assistance, please contact us at support@ecosyste.ms.
  
      Thank you for your continued contributions to the #{fund.name} open source community!
    DESCRIPTION
  end

  def expense_invite_description
    if invitation.present? && invitation.accepted?
      <<~DESCRIPTION
        You are receiving this message because you confirmed you are happy to accept a donation for your work within the #{fund.name} open source ecosystem.
  
        To complete the donation we need some further information from you. Please complete the linked form in order for our team to process your payment promptly.
  
        For more information, please visit our FAQ at https://funds.ecosyste.ms/faq.

        If you have any questions or need assistance, please contact us at support@ecosyste.ms.
  
        Thank you for your incredible contributions to the #{fund.name} open source community!
      DESCRIPTION
    else
      <<~DESCRIPTION
        You are receiving this message because we have not yet received a response regarding a donation for your work within the #{fund.name} open source ecosystem.
  
        If you wish to accept this donation, please complete the linked form in order for our team to process your payment promptly.
  
        For more information, please visit our FAQ at https://funds.ecosyste.ms/faq.

        If you have any questions or need assistance, please contact us at support@ecosyste.ms.
  
        Thank you for your contributions to the #{fund.name} open source community!
      DESCRIPTION
    end
  end

  def send_expense_invite
    return { skipped: 'funding_rejected' } if funding_rejected?
    return { skipped: 'has_approved_funding_source' } if approved_funding_source?
    return { skipped: 'no_contact_email' } unless project.contact_email.present?
    return { skipped: 'invitation_already_sent', invitation_id: invitation.member_invitation_id } if invitation.present? && invitation.member_invitation_id.present?
    return { skipped: 'already_paid' } if paid?

    query = <<~GRAPHQL
      mutation($expense: ExpenseInviteDraftInput!, $account: AccountReferenceInput!) {
        draftExpenseAndInviteUser(expense: $expense, account: $account, skipInvite: true, lockedFields: [AMOUNT, DESCRIPTION, TYPE, PAYEE]) {
          id
          legacyId
          draft
          lockedFields
          account {
            id
            slug
          }
          payee {
            ... on Individual {
              id
              email
            }
            ... on Organization {
              id
            }
          }
          status
          draftKey
        }
      }
    GRAPHQL

    variables = {
      expense: {
        description: "#{fund.name} Ecosystem allocation for #{project.to_s}",
        currency: "USD",
        type: "INVOICE",
        payee: {
          name: "#{project.to_s} maintainer",
          email: project.contact_email
        },
        items: [
          {
            description: expense_invite_title,
            longDescription: expense_invite_description,
            amount: amount_cents,
            currency: "USD"
          }
        ]
      },
      account: {
        slug: fund.oc_project_slug
      }
    }

    response_body = oc_api_request(query: query, variables: variables, event_type: 'payout_expense_invite')
    return nil unless response_body

    data = response_body['data']['draftExpenseAndInviteUser']
    puts "Expense draft created successfully:"
    puts JSON.pretty_generate(data)
    inv = Invitation.create!(project_allocation: self, email: project.contact_email, status: 'DRAFT', member_invitation_id: data['legacyId'], data: data)
    log_event('expense_created', invitation_record: inv, metadata: { legacy_id: data['legacyId'] })
    inv
  end

  def send_to_osc_collective(collective_slug, amount_cents)
    return if funding_rejected?

    query = <<-GQL
      mutation(
        $fromAccount: AccountReferenceInput!,
        $toAccount: AccountReferenceInput!,
        $amount: AmountInput!,
        $frequency: ContributionFrequency!,
        $isBalanceTransfer: Boolean!,
        $paymentMethodId: String!
      ) {
        createOrder(order: {
          fromAccount: $fromAccount,
          toAccount: $toAccount,
          amount: $amount,
          frequency: $frequency,
          isBalanceTransfer: $isBalanceTransfer,
          paymentMethod: { id: $paymentMethodId }
        }) {
          order {
            id
            status
            amount {
              value
              currency
            }
          }
        }
      }
    GQL

    variables = {
      fromAccount: { slug: fund.oc_project_slug },
      toAccount: { slug: collective_slug },
      amount: { currency: "USD", valueInCents: amount_cents },
      frequency: "ONETIME",
      isBalanceTransfer: true,
      paymentMethodId: fund.osc_payment_method['id']
    }

    response_body = oc_api_request(query: query, variables: variables, event_type: 'payout_osc_collective')
    return nil unless response_body

    puts "Order created successfully:"
    puts JSON.pretty_generate(response_body['data']['createOrder'])
    response_body['data']['createOrder']
  end

  def expense_invite_title
    "#{fund.name} Ecosystem Funds Sponsorship Invitation for #{project.name}"
  end

  def send_draft_expense_invitation_to_collective(collective_slug, amount_cents, description)
    return if funding_rejected?
    return if paid?

    query = <<-GQL
      mutation(
        $account: AccountReferenceInput!,
        $expense: ExpenseInviteDraftInput!
      ) {
        draftExpenseAndInviteUser(
          account: $account,
          expense: $expense,
          lockedFields: [AMOUNT],
          skipInvite: true
        ) {
          id
          status
          draftKey
          amount
          currency
          description
          legacyId
          payee {
            ... on Collective {
              slug
            }
          }
        }
      }
    GQL

    variables = {
      account: { slug: fund.oc_project_slug },
      expense: {
        description: expense_invite_title,
        longDescription: description,
        currency: "USD",
        type: "INVOICE",
        items: [{ amount: amount_cents, description: description }],
        payee: {
          slug: collective_slug,
          isInvite: true
        },
        payoutMethod: {
          data: {},
          isSaved: false
        }
      }
    }

    response_body = oc_api_request(query: query, variables: variables, event_type: 'payout_non_osc_collective')
    return nil unless response_body

    data = response_body['data']['draftExpenseAndInviteUser']
    puts "Draft expense created successfully and invitation sent:"
    puts JSON.pretty_generate(data)
    inv = Invitation.create!(project_allocation: self, email: project.contact_email, status: 'DRAFT', member_invitation_id: data['legacyId'], data: data)
    log_event('expense_created', invitation_record: inv, metadata: { legacy_id: data['legacyId'] })
    data
  end

  def send_expense_to_vendor(vendor, amount_cents)
    return if funding_rejected?
    return if paid?

    description = proxy_collective_expense_invite_description(vendor)

    query = <<-GQL
      mutation(
        $account: AccountReferenceInput!,
        $expense: ExpenseCreateInput!,
      ) {
        createExpense(
          account: $account,
          expense: $expense,
        ) {
          id
          status
          draftKey
          amount
          currency
          description
          legacyId
          payee {
            ... on Collective {
              slug
            }
          }
        }
      }
    GQL

    variables = {
      account: { slug: fund.oc_project_slug },
      expense: {
        description: expense_invite_title,
        longDescription: description,
        currency: "USD",
        type: "INVOICE",
        items: [{ amount: amount_cents, description: description }],
        payee: {
          slug: vendor.slug
        },
        payoutMethod: { type: "ACCOUNT_BALANCE" },
        tags: [vendor.platform, "ecosystem-fund"],
        accountingCategory: { id: "3vjrkx5l-mnv904qj-jmq8bwa7-zdygoe3d" }
      }
    }

    response_body = oc_api_request(query: query, variables: variables, event_type: 'payout_proxy_collective')
    return nil unless response_body

    data = response_body['data']['createExpense']
    puts "Draft expense created successfully and invitation sent:"
    puts JSON.pretty_generate(data)
    inv = Invitation.create!(project_allocation: self, email: project.contact_email, status: 'DRAFT', member_invitation_id: data['legacyId'], data: data)
    log_event('expense_created', invitation_record: inv, metadata: { legacy_id: data['legacyId'], vendor_slug: vendor.slug })
    inv
  end

  def check_collective_existence(slug)
    query = <<-GQL
      query($slug: String!) {
        account(slug: $slug) {
          id
          slug
        }
      }
    GQL
  
    variables = { slug: slug }
    payload = { query: query, variables: variables }.to_json
  
    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )
  
    response_body = JSON.parse(response.body)
    
    if response_body['data'] && response_body['data']['account']
      puts "Collective exists with slug: #{slug}"
      return response_body['data']['account']
    elsif response_body['errors']
      puts "Error checking collective existence: #{response_body['errors']}"
      return nil
    else
      puts "No existing collective with slug: #{slug}"
      return nil
    end
  end

  def find_or_create_proxy_collective(url)
    ProxyCollective.find_or_create_by_website(url)
  end

  def add_funds_to_proxy_collective(proxy_collective_slug, amount_cents, description)
    return if funding_rejected?
    query = <<-GQL
      mutation AddFunds($fromAccount: AccountReferenceInput!, $account: AccountReferenceInput!, $amount: AmountInput!, $description: String!) {
        addFunds(
          fromAccount: $fromAccount,
          account: $account,
          amount: $amount,
          description: $description
        ) {
          id
          amount {
            value
            currency
          }
          description
        }
      }
    GQL

    variables = {
        "fromAccount": { "slug": fund.oc_project_slug },
        "account": { "slug": proxy_collective_slug },
        "amount": { "valueInCents": amount_cents, "currency": "USD" },
        "description": "Funding for proxy collective services"
    }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )
  
    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error adding funds to proxy collective: #{response_body['errors']}"
    else
      puts "Funds added to proxy collective successfully:"
      puts JSON.pretty_generate(response_body['data']['addFunds'])
      response_body['data']['addFunds']
    end
  end

  def funder_names
    allocation.funder_names
  end

  def decline_deadline
    created_at + 14.days
  end

  def allocation_payout_date
    created_at + 28.days
  end

  def create_invite
    return if funding_source.present?
    return if invitation.present?
      
    Invitation.create!(project_allocation: self, email: project.contact_email)  
  end

  def send_invitation
    return if funding_source.present?
    return if invitation.present?
    return if funding_rejected?

    inv = create_invite
    return unless inv

    log_event('invitation_created', invitation_record: inv, metadata: { email: inv.email })
    inv.send_email
    inv
  end

  def send_expense_invite_email
    return unless invitation.present?
    invitation.send_expense_invite_email
  end

  def reject_funding!
    project.update!(funding_rejected: true)
    log_event('funding_rejected', message: "Funding rejected for project: #{project.to_s}")
    project.project_allocations.each do |pa|
      next unless pa.invitation.present?
      pa.invitation.update!(rejected_at: Time.now)
      pa.log_event('invitation_rejected', invitation_record: pa.invitation)
    end
  end

  def accept_funding!
    project.update!(funding_rejected: false)
    log_event('funding_accepted', message: "Funding accepted for project: #{project.to_s}")
    project.project_allocations.each do |pa|
      next unless pa.invitation.present?
      pa.invitation.update!(accepted_at: Time.now)
      pa.log_event('invitation_accepted', invitation_record: pa.invitation)
    end
  end

  def funding_rejected?
    project.funding_rejected?
  end

  def invitation_accepted?
    invitation.present? && invitation.accepted_at.present?
  end

  def potential_transactions
    Transaction.where(amount: -(amount_cents)/100.0)
  end

  def find_transaction
    # if invitation use its data['legacyId']
    if potential_transactions.length == 1
      return potential_transactions.first
    else
      potential_transactions.select{|t| t.account == funding_source.name }.first
    end
  end

  def status
    return 'REJECTED' if funding_rejected?
    return invitation.status if invitation.present?
    return 'PAID' if find_transaction.present?
  end

  def success?
    ['APPROVED', 'PAID'].include?(status)
  end

  def log_event(event_type, status: 'success', message: nil, metadata: {}, invitation_record: nil)
    events.create!(
      event_type: event_type,
      status: status,
      message: message,
      metadata: metadata,
      fund_id: fund_id,
      allocation_id: allocation_id,
      invitation: invitation_record
    )
  end
end
