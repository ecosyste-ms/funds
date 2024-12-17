class ProjectAllocation < ApplicationRecord
  belongs_to :project
  belongs_to :allocation
  belongs_to :fund
  belongs_to :funding_source, optional: true
  has_one :invitation

  scope :with_funding_source, -> { where.not(funding_source_id: nil) }
  scope :with_approved_funding_source, -> { joins(:funding_source).where(funding_sources: { platform: FundingSource::APPROVED_PLATFORMS }) }
  scope :without_funding_source, -> { where(funding_source_id: nil) }

  scope :platform, ->(platform) { joins(:funding_source).where(funding_sources: { platform: platform }) }

  def update_funding_source
    return if funding_source_id.present?
    self.funding_source_id = project.funding_source_id
    save
  end

  def approved_funding_source?
    funding_source && funding_source.approved?
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

  def payout
    return if funding_rejected?

    if is_osc_collective?
      puts "  Sending to OSC collective: #{funding_source.name}"
      send_to_osc_collective(collective_slug, amount_cents)
    elsif is_non_osc_collective?
      puts "  Sending to non-OSC collective: #{funding_source.name}"
      send_draft_expense_invitation(collective_slug, amount_cents, description) # TODO record this an an invitation as well
    elsif approved_funding_source?
      puts "  Sending to approved funding source: #{funding_source.url}"
      proxy_collective = find_or_create_proxy_collective(funding_source.url)
      if proxy_collective
        puts "  Adding funds to proxy collective: #{proxy_collective.slug}" 
        send_to_osc_collective(proxy_collective.slug, amount_cents)
      end
    elsif project && project.contact_email.present?
      puts "  Sending expense invite: #{project.contact_email}"
      send_expense_invite
    else
      puts "  No valid payout method found for #{project.to_s}"
       # can't pay
    end
  end

  def send_expense_invite
    return if funding_rejected?
    return if approved_funding_source?
    return unless project.contact_email.present?
    return if invitation.present?
    
    query = <<~GRAPHQL
      mutation($expense: ExpenseInviteDraftInput!, $account: AccountReferenceInput!) {
        draftExpenseAndInviteUser(expense: $expense, account: $account, skipInvite: true, lockedFields: [AMOUNT, DESCRIPTION, TYPE]) {
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
          name: "#{project.to_s} maintainer", # TODO try to get the maintainer name
          email: "#{project.contact_email.gsub('@', '+test')}@test.com" # Use a test email for now
        },
        items: [
          {
            description: "Allocation for #{project.to_s}",
            amount: amount_cents,
            currency: "USD"
          }
        ]
      },
      account: {
        slug: fund.oc_project_slug
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
      puts "Expense draft created successfully:"
      puts JSON.pretty_generate(response_body['data']['draftExpenseAndInviteUser'])
      Invitation.create!(project_allocation: self, email: project.contact_email, status: 'DRAFT', member_invitation_id: response_body['data']['draftExpenseAndInviteUser']['legacyId'], data: response_body['data']['draftExpenseAndInviteUser'])
    end
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
      puts "Order created successfully:"
      puts JSON.pretty_generate(response_body['data']['createOrder'])
      response_body['data']['createOrder']
    end
  end

  def send_draft_expense_invitation(collective_slug, amount_cents, description)
    return if funding_rejected?
    query = <<-GQL
      mutation(
        $account: AccountReferenceInput!,
        $expense: ExpenseInviteDraftInput!
      ) {
        draftExpenseAndInviteUser(
          account: $account,
          expense: $expense,
          skipInvite: true
        ) {
          id
          status
          draftKey
          amount
          currency
          description
          payee {
            ... on Collective {
              slug
            }
          }
        }
      }
    GQL
  
    variables = {
      account: { slug: fund.oc_project_slug },          # Collective initiating the expense draft
      expense: {
        description: description,
        longDescription: description,
        currency: "USD",
        type: "INVOICE",
        items: [{ amount: amount_cents, description: description }],
        payee: {
          slug: collective_slug,
          isInvite: true                                # Marking as an invite for the payee collective
        },
        payoutMethod: { type: "ACCOUNT_BALANCE" }       # Specify payout method, adjust if needed
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
      puts "Draft expense created successfully and invitation sent:"
      puts JSON.pretty_generate(response_body['data']['draftExpenseAndInviteUser'])
      response_body['data']['draftExpenseAndInviteUser']
    end
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

  def create_invite
    return if funding_source.present?
    return if invitation.present?
      
    Invitation.create!(project_allocation: self, email: project.contact_email)  
  end

  def send_invitation
    return if funding_source.present?
    return if invitation.present?
    
    invitation = create_invite
    
    invitation.try(:send_email)
  end

  def reject_funding!
    project.update!(funding_rejected: true) 
    # reject all other invitations for the same project
    project.project_allocations.each do |pa|
      next unless pa.invitation.present?
      pa.invitation.update!(rejected_at: Time.now)
    end
  end

  def accept_funding!
    project.update!(funding_rejected: false)
    # accept all other invitations for the same project
    project.project_allocations.each do |pa|
      next unless pa.invitation.present?
      pa.invitation.update!(accepted_at: Time.now)
    end
  end

  def funding_rejected?
    project.funding_rejected?
  end

  def invitation_accepted?
    invitation.present? && invitation.accepted_at.present?
  end
end
