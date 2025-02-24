class Fund < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  has_many :allocations
  has_many :project_allocations, through: :allocations
  has_many :projects, through: :project_allocations
  has_many :transactions

  scope :project_legacy_id, ->(id) { where("opencollective_project->>'legacyId' = ?", id) }

  scope :featured, -> { where(featured: true) }
  scope :not_featured, -> { where(featured: false) }
  scope :short_names, -> { where("LENGTH(name) < ?", 20) }

  def self.search(query)
    where("name ILIKE :query OR description ILIKE :query", query: "%#{query}%")
      .left_joins(:allocations)
      .group("funds.id")
      .order("COUNT(allocations.id) DESC")
  end

  def self.sync_least_recently_synced    
    Fund.featured.where(last_synced_at: nil).or(Fund.where("last_synced_at < ?", 1.day.ago)).order('last_synced_at asc nulls first').limit(10).each do |fund|
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
      fund.topic_logo_url = topic['logo_url']
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
    fund.topic_logo_url = topic['logo_url']

    fund.save!
    return fund
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
    if topic_logo_url.present?
      topic_logo_url
    elsif github_owner_url.present?
      github_owner_url + '.png'
    else
      "https://explore-feed.github.com/topics/#{slug}/#{slug}.png"
    end
  end

  def github_owner_url
    return nil if github_url.blank?
    github_url.split('/')[0..3].join('/')
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
      break if page > 10
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
        if package['registry']
          registry_name = package['registry']['name'] 
          project.registry_names += [registry_name] unless project.registry_names.include?(registry_name)
        end
        all_keywords = []
        all_keywords += Array(package['repo_metadata']["topics"]) if package['repo_metadata'].present?
        all_keywords += Array(package["keywords"])
        project.keywords = all_keywords.reject(&:blank?).uniq { |keyword| keyword.downcase }.dup
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
    return unless possible_projects.any?
    
    allocate(current_balance_cents)
  end

  def has_funds_for_allocation?
    current_balance_cents >= minimum_for_allocation_cents
  end

  def allocate(total_cents)
    return unless possible_projects.any?
    return if total_cents < minimum_for_allocation_cents
    
    allocations = Allocation.where(fund_id: id, year: Time.zone.now.year, month: Time.zone.now.month)
    return if allocations.any?

    allocations = Allocation.create!(fund_id: id, year: Time.zone.now.year, month: Time.zone.now.month, total_cents: total_cents)
    allocations.calculate_funded_projects
  end

  def possible_projects
    if primary_topic.present?
      # TODO include aliases
      Project.keyword(all_keywords).exclude_keywords(excluded_topics).not_rejected_funding
    elsif registry_name.present?
      Project.registry_name(registry_name).not_rejected_funding
    end
  end

  def open_collective_project_url
    return nil if opencollective_project_id.blank?
    "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{oc_project_slug}"
  end

  def open_collective_project_embed_url
    return nil if opencollective_project_id.blank?
    "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/embed/#{ENV['OPENCOLLECTIVE_PARENT_SLUG']}/projects/#{oc_project_slug}/donate?hideSteps=false&hideFAQ=true&hideHeader=false"
  end

  def open_collective_project_donate_url
    return nil if opencollective_project_id.blank?
    "#{open_collective_project_url}/donate"
  end

  def invoice_mailto_url
    "mailto:hello@oscollective.org?subject=#{name} Fund Invoice&body=Please send an invoice for the #{name} Fund to the following address:"
  end

  def oc_project_slug
    "oc-#{slug}-fund"
  end

  def sync_opencollective_project_async
    SyncFundProjectWorker.perform_async(id)
  end

  def sync_opencollective_project
    return unless featured?
    if opencollective_project_id.present?
      fetch_opencollective_project
    else
      setup_opencollective_project
      update_social_links
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
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPEN_COLLECTIVE_API_KEY']}",
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

  def update_social_links
    query = <<~GRAPHQL
      mutation UpdateSocialLinks($account: AccountReferenceInput!, $socialLinks: [SocialLinkInput!]!) {
        updateSocialLinks(account: $account, socialLinks: $socialLinks) {
          type
          url
          createdAt
          updatedAt
        }
      }
    GRAPHQL

    variables = {
      account: { slug: oc_project_slug },
      socialLinks: [
        { type: "WEBSITE", url: "https://funds.ecosyste.ms/funds/#{slug}" }
      ]
    }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"

    response_data = JSON.parse(response.body)

    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
    else
      return response_data['data']['updateSocialLinks']
    end
  end

  def setup_opencollective_project
    return unless featured?
    return if opencollective_project_id.present?
  
    file = download_image(logo_url)
    return unless file
  
    query = <<~GRAPHQL
      mutation CreateProject($parent: AccountReferenceInput!, $project: ProjectCreateInput!) {
        createProject(parent: $parent, project: $project) {
          id
          legacyId
          name
          description
          slug
          tags
          imageUrl
          createdAt
          updatedAt
        }
      }
    GRAPHQL
  
    operations = {
      query: query,
      variables: {
        parent: { slug: ENV['OPENCOLLECTIVE_PARENT_SLUG'] },
        project: {
          name: "#{name} Fund",
          slug: oc_project_slug,
          description: "Supporting maintainers and communities in the #{name} ecosystem.",
          tags: ["open-source", "community", "fund", slug],
          socialLinks: { website: "https://funds.ecosyste.ms/funds/#{slug}" },
          image: nil # Placeholder for the file reference
        }
      }
    }.to_json
  
    map = {
      "1" => ["variables.project.image"]
    }.to_json
  
    payload = {
      operations: Faraday::Multipart::ParamPart.new(operations, 'application/json'),
      map: Faraday::Multipart::ParamPart.new(map, 'application/json'),
      "1" => Faraday::Multipart::FilePart.new(file.path, 'image/png', 'logo.png')
    }
  
    connection = Faraday.new(url: "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}") do |faraday|
      faraday.request :multipart
      faraday.adapter Faraday.default_adapter
    end
  
    response = connection.post do |req|
      req.url "/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}"
      req.headers['Authorization'] = "Bearer #{ENV['OPENCOLLECTIVE_TOKEN']}" # Authorization header
      req.headers['Personal-Token'] = ENV['OPENCOLLECTIVE_TOKEN'] # Personal-Token header
      req.body = payload
    end
  
    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"
  
    response_data = JSON.parse(response.body)
  
    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
    else
      project_data = response_data.dig('data', 'createProject')
      if project_data
        puts "Project created! ID: #{project_data['id']}, Name: #{project_data['name']}, Description: #{project_data['description']}"
        self.opencollective_project_id = project_data['id']
        self.opencollective_project = project_data
        save
        return project_data
      else
        raise "Project creation failed"
      end
    end
  ensure
    file.close if file
    file.unlink if file
  end

  def download_image(url)
    return nil if url.blank?
  
    begin
      tempfile = Tempfile.new(['logo', '.png'])
      URI.open(url) do |image|
        tempfile.binmode
        tempfile.write(image.read)
      end
      tempfile.rewind
      tempfile
    rescue => e
      puts "Failed to download image: #{e.message}"
      nil
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
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
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

  def total_donors
    transactions.donations.distinct.count(:account)
  end

  def total_distributed_cents
    allocations.sum(&:total_allocated_cents)
  end

  def total_funded_projects
    allocations.sum{|a| a.funded_projects_count || 0 }
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
          account_name: node['type'] == 'DEBIT' ? node['toAccount']['name'] : node['fromAccount']['name'],
          account_image_url: node['type'] == 'DEBIT' ? node['toAccount']['imageUrl'] : node['fromAccount']['imageUrl'],
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
    graphql_url = "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}"

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
              name
              imageUrl
            }
            fromAccount {
              slug
              name
              imageUrl
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
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
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

  def funder_names
    transactions.donations.distinct.pluck(:account_name)
  end

  def funders
    transactions.donations.map{|t| {name: t.account_name, slug: t.account, image_url: t.account_image_url, amount: t.amount}}
      .group_by { |t| t[:slug] }
      .map { |slug, txns| { slug: slug, name: txns.first[:name], image_url: txns.first[:image_url], amount: txns.sum { |t| t[:amount] } } }
      .sort_by { |f| -f[:amount] }
  end
end
