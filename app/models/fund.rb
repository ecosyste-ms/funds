class Fund < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  has_many :allocations
  has_many :project_allocations, through: :allocations
  has_many :projects, through: :project_allocations
  has_many :transactions

  scope :project_legacy_id, ->(id) { where("opencollective_project->>'legacyId' = ?", id) }

  def self.sync_least_recently_synced    
    Fund.where(last_synced_at: nil).or(Fund.where("last_synced_at < ?", 1.day.ago)).order('last_synced_at asc nulls first').limit(500).each do |fund|
      fund.sync_async
    end
  end

  def to_param
    slug
  end

  def to_s
    name
  end

  def default_minimum_for_allocation_cents
    100_00
  end

  def minimum_for_allocation_cents
    super || default_minimum_for_allocation_cents
  end

  def self.import_suggested_topics
    url = "https://awesome.ecosyste.ms/api/v1/topics/suggestions?per_page=1000"

    resp = Faraday.get url
    return unless resp.status == 200

    data = JSON.parse(resp.body)
    data.each do |topic|
      fund = Fund.find_or_create_by(name: topic['name'], slug: topic['slug'])
      fund.primary_topic = topic['slug']
      fund.secondary_topics = topic['aliases']
      fund.description = topic['short_description']
      fund.wikipedia_url = topic['wikipedia_url']
      fund.github_url = topic['github_url']
      fund.save!
    end
  end

  def self.import_from_topic(topic)
    topic_url = "https://awesome.ecosyste.ms/api/v1/topics/#{topic}"

    resp = Faraday.get topic_url
    return unless resp.status == 200
      
    topic = JSON.parse(resp.body)

    fund = Fund.find_or_create_by(name: topic['name'], slug: topic['slug'])
    
    fund.primary_topic = topic['slug']
    fund.secondary_topics = topic['aliases']
    fund.description = topic['short_description']
    fund.wikipedia_url = topic['wikipedia_url']
    fund.github_url = topic['github_url']

    fund.save!
  end

  def sync
    sync_opencollective_project
    if registry_name.present?
      import_projects_from_critical_packages
    else
      import_projects
    end
  end

  def sync_async
    SyncFundWorker.perform_async(id)
  end

  def logo_url
    "https://explore-feed.github.com/topics/#{slug}/#{slug}.png"
  end

  def all_keywords
    [primary_topic, *secondary_topics].compact
  end

  def import_projects
    all_keywords.each do |keyword|
      import_projects_from_packages(keyword)
    end
  end

  def import_projects_from_packages(keyword)
    page = 1
    loop do
      break if page > 30
      puts "Fetching page #{page} of projects for #{name}"
      resp = Faraday.get("https://packages.ecosyste.ms/api/v1/keywords/#{keyword}?per_page=100&page=#{page}")
      break unless resp.status == 200
  
      data = JSON.parse(resp.body)
      packages = data['packages']
      break if packages.empty?
  
      packages = packages.reject { |p| p['status'].present? || p['repository_url'].blank? }
      packages.each do |package|
        project = Project.find_or_create_by(url: package['repository_url'])
        project.repository = package['repo_metadata'] if project.repository.blank?
        project.packages += [package] unless project.packages.map{|pkg| pkg['registry_url']}.include?(package['registry_url'])
        project.save
        project.sync_async unless project.last_synced_at.present?
      end
  
      page += 1
    end
  end

  def import_projects_from_critical_packages
    return unless registry_name.present?
    page = 1
    loop do
      puts "Fetching page #{page} of projects for #{name}"
      resp = Faraday.get("https://packages.ecosyste.ms/api/v1/registries/#{registry_name}/packages?critical=true&per_page=100&page=#{page}")
      break unless resp.status == 200

      data = JSON.parse(resp.body)
      packages = data
      break if packages.empty?

      packages = packages.reject { |p| p['repository_url'].blank? }
      packages.each do |package|
        project = Project.find_or_create_by(url: package['repository_url'])
        project.repository = package['repo_metadata'] if project.repository.blank?
        project.packages += [package] unless project.packages.map{|pkg| pkg['registry_url']}.include?(package['registry_url'])
        project.registry_names += [registry_name] unless project.registry_names.include?(registry_name)
        project.save
        project.sync_async unless project.last_synced_at.present?
      end

      page += 1
    end
  end

  def current_balance_cents
    current_balance * 100
  end

  def allocate_to_projects
    return unless has_funds_for_allocation?
    
    allocate(current_balance_cents)
  end

  def has_funds_for_allocation?
    current_balance_cents >= minimum_for_allocation_cents
  end

  def allocate(total_cents)
    return if total_cents < minimum_for_allocation_cents
    
    allocations = Allocation.where(fund_id: id, year: Time.zone.now.year, month: Time.zone.now.month)
    return if allocations.any?

    allocations = Allocation.create!(fund_id: id, year: Time.zone.now.year, month: Time.zone.now.month, total_cents: total_cents)
    allocations.calculate_funded_projects
  end

  def possible_projects
    if primary_topic.present?
      # TODO include aliases
      Project.keyword(primary_topic).active.with_license
    elsif registry_name.present?
      Project.registry_name(registry_name).active.with_license
    end
  end

  def open_collective_project_url
    return nil if opencollective_project_id.blank?
    "https://staging.opencollective.com/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{oc_project_slug}"
  end

  def oc_project_slug
    "oc-#{slug}-fund"
  end

  def sync_opencollective_project_async
    SyncFundProjectWorker.perform_async(id)
  end

  def sync_opencollective_project
    if opencollective_project_id.present?
      fetch_opencollective_project
    else
      setup_opencollective_project
    end
    setup_webhook
    sync_transactions
    update_column(:last_synced_at, Time.zone.now)
  end

  def fetch_opencollective_project
    query = <<~GRAPHQL
      query($slug: String!) {
        project(slug: $slug) {
          id
          legacyId
          name
          description
          slug
          tags
          createdAt
          updatedAt
        }
      }
    GRAPHQL

    variables = { slug: oc_project_slug }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPEN_COLLECTIVE_API_KEY']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    begin
      response_data = JSON.parse(response.body)
  
      if response_data['data'] && response_data['data']['project']
        project_data = response_data['data']['project']
        update!(opencollective_project: project_data, opencollective_project_id: project_data['id']) 
      else
        puts "No project data found. Response: #{response.body}"
      end
    rescue JSON::ParserError => e
      puts "Failed to parse response: #{e.message}"
    end

  end

  def setup_opencollective_project
    return if opencollective_project_id.present?

    query = <<~GRAPHQL
      mutation CreateProject($parent: AccountReferenceInput!, $project: ProjectCreateInput!) {
        createProject(parent: $parent, project: $project) {
          id
          legacyId
          name
          description
          slug
          type
          tags
          website
          imageUrl
          createdAt
          updatedAt
        }
      }
    GRAPHQL
  
    variables = {
      parent: { slug: ENV['OPENCOLLECTIVE_PARENT_SLUG'] },
      project: {
        name: "#{name} Fund",
        slug: oc_project_slug,
        description: "This is the Open Collective for the #{name} Fund. We support open-source projects in the #{name} ecosystem.",
        tags: ["open-source", "community", "fund", slug],
      }
    }
  
    payload = { query: query, variables: variables }.to_json
  
    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )
  
    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"
  
    response_data = JSON.parse(response.body)
  
    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
      # TODO if slug already exists, load the project and save the id
    else
      project_data = response_data['data']['createProject']
      puts "Project created! ID: #{project_data['id']}, Name: #{project_data['name']}, Description: #{project_data['description']}"
      self.opencollective_project_id = project_data['id']
      self.opencollective_project = project_data
      save
      return project_data
    end
  end

  def add_image_to_opencollective_project
    return unless opencollective_project_id.present?

    query = <<~GRAPHQL
    mutation EditAccountSetting($account: AccountReferenceInput!, $key: String!, $value: JSON!) {
      editAccountSetting(account: $account, key: $key, value: $value) {
        id
        name
        settings
      }
    }
  GRAPHQL
  
  variables = {
    account: { id: opencollective_project_id },
    key: "collective.image",
    value: logo_url
  }

    payload = { query: query, variables: variables }.to_json
  
    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )
  
    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"
  
    response_data = JSON.parse(response.body)
  
    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
      # TODO if slug already exists, load the project and save the id
    else
      account_data = response_data['data']['editAccount']
      puts "Account edited! ID: #{account_data['id']}, Name: #{account_data['name']}, Image URL: #{account_data['imageUrl']}"
      return account_data
    end
  end

  def setup_webhook
    return if opencollective_project_id.blank?
    return if oc_webhook_id.present?

    query = <<~GRAPHQL
      mutation ($webhook: WebhookCreateInput!) {
        createWebhook(webhook: $webhook) {
          id
          legacyId
          activityType
          webhookUrl
        }
      }
    GRAPHQL

    variables = {
      webhook: {
        account: { id: opencollective_project_id, slug: oc_project_slug },
        activityType: "ACTIVITY_ALL",
        webhookUrl: "https://funds.ecosyste.ms/webhooks"
      }
    } 

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"

    response_data = JSON.parse(response.body)

    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
    else
      webhook_data = response_data['data']['createWebhook']
      puts "Webhook created! ID: #{webhook_data['id']}, URL: #{webhook_data['webhookUrl']}"
      self.oc_webhook_id = webhook_data['id']
      save
      return webhook_data
    end

  end

  def total_donations
    transactions.donations.sum(:net_amount) + transactions.host_fees.sum(:net_amount)
  end

  def total_expenses
    transactions.expenses.sum(:net_amount)
  end

  def current_balance
    transactions.sum(:net_amount)
  end

  def sync_transactions
    first_page = fetch_transactions_from_graphql # TODO handle errors
    total_count = first_page['data']['transactions']['totalCount']
    puts "Total count: #{total_count}"
    offset = 0
    while offset < total_count
      puts "Loading transactions #{offset}"
      page = fetch_transactions_from_graphql(offset: offset)
      transactions = page['data']['transactions']['nodes'].map do |node|
        {
          fund_id: id,
          legacy_id: node['legacyId'],
          uuid: node['uuid'],
          amount: node['amount']['value'],
          net_amount: node['netAmount']['value'],
          transaction_type: node['type'],
          transaction_kind: node['kind'],
          transaction_expense_type: node['expense'] ? node['expense']['type'] : nil,
          currency: node['amount']['currency'],
          account: node['type'] == 'DEBIT' ? node['toAccount']['slug'] : node['fromAccount']['slug'],
          order: node['order'],
          created_at: node['createdAt'],
          description: node['description']
        }
      end
      Transaction.upsert_all(transactions, unique_by: :uuid)
      offset += 1000
    end
    update(balance: current_balance)
  end

  def fetch_transactions_from_graphql(offset: 0)
    graphql_url = "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}"

    query = <<~GRAPHQL
      query Transactions(
        $account: [AccountReferenceInput!]
        $limit: Int
        $offset: Int
      ) {
        transactions(
          account: $account
          limit: $limit
          offset: $offset
        ) {
          offset
          limit
          totalCount
          nodes {
            legacyId
            uuid
            amount {
              value
              currency
            }
            description
            netAmount {
              value
              currency
            }            
            createdAt
            type
            kind
            order {
              id
              legacyId
              description
              quantity
              status
              frequency
              nextChargeDate
              createdAt
              updatedAt
              hostFeePercent
              platformTipEligible
              tags
              data
              customData
              memo
              processedAt
              needsConfirmation
            }
            expense {
              type
            }
            toAccount {
              slug
            }
            fromAccount {
              slug
            }
          }
        }
      }
    GRAPHQL

    conn = Faraday.new(url: graphql_url) do |faraday|
      faraday.response :follow_redirects
      faraday.adapter Faraday.default_adapter
    end

    resp = conn.post do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = { query: query, variables: { account: { slug: oc_project_slug }, limit: 1000, offset: offset } }.to_json
    end

    JSON.parse(resp.body)
  end

  def get_all_oc_payment_methods
    query = <<-GQL
      query($accountSlug: String!) {
        account(slug: $accountSlug) {
          paymentMethods {
            id
            service
            type
          }
        }
      }
    GQL

    variables = { accountSlug: oc_project_slug }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"

    response_data = JSON.parse(response.body)

    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
    else
      return response_data['data']['account']['paymentMethods']
    end
  end

  def osc_payment_method
    get_all_oc_payment_methods.find { |pm| pm['service'] == 'OPENCOLLECTIVE' }
  end
end
