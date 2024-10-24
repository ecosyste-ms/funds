class ProjectAllocation < ApplicationRecord
  belongs_to :project
  belongs_to :allocation
  belongs_to :fund
  belongs_to :funding_source, optional: true
  has_one :invitation

  scope :with_funding_source, -> { where.not(funding_source_id: nil) }
  scope :without_funding_source, -> { where(funding_source_id: nil) }

  scope :platform, ->(platform) { joins(:funding_source).where(funding_sources: { platform: platform }) }

  def approved_funding_source?
    funding_source && funding_source.approved?
  end

  def send_expense_invite
    return if approved_funding_source?
    return unless project.contact_email.present?
    return if invitation.present?
    
    query = <<~GRAPHQL
      mutation($expense: ExpenseInviteDraftInput!, $account: AccountReferenceInput!) {
        draftExpenseAndInviteUser(expense: $expense, account: $account) {
          id
          legacyId
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
            amount: amount_cents
          }
        ]
      },
      account: {
        slug: fund.oc_project_slug
      }
    }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
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
end
