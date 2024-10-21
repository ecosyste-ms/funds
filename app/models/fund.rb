class Fund < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  has_many :allocations
  has_many :project_allocations, through: :allocations
  has_many :projects, through: :project_allocations

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

  def sync_opencollective_project
    if opencollective_project_id.present?
      fetch_opencollective_project
    else
      setup_opencollective_project
    end
  end

  def fetch_opencollective_project
    return if opencollective_project_id.blank?
    
    query = <<~GRAPHQL
      query($id: String!) {
        project(id: $id) {
          id
          name
          description
          slug
          tags
          createdAt
          updatedAt
        }
      }
    GRAPHQL

    variables = { id: opencollective_project_id }

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
        update!(opencollective_project: project_data) # Save project data to your JSON field
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
          name
          description
          slug
          tags
          createdAt
          updatedAt
        }
      }
    GRAPHQL
  
    variables = {
      parent: { slug: ENV['OPENCOLLECTIVE_PARENT_SLUG'] },
      project: {
        name: "#{name} Fund",
        slug: "oc-#{slug}-fund",
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
    else
      project_data = response_data['data']['createProject']
      puts "Project created! ID: #{project_data['id']}, Name: #{project_data['name']}, Description: #{project_data['description']}"
      self.opencollective_project_id = project_data['id']
      self.opencollective_project = project_data
      save
      return project_data
    end
  end
end
