class ProxyCollective < ApplicationRecord

  PROXY_PARENT_COLLECTIVE_SLUG = ENV['PROXY_PARENT_COLLECTIVE_SLUG'] || 'ecosystem-funds'

  def self.find_or_create_by_website(url)
    find_by_website(url) || create_by_website(url)
  end

  def self.find_by_website(url)
    find_by(website: url)
  end

  def self.slug_from_url(url)
    platform = platform_from_url(url)
    username = username_from_url(url, platform)
    "esf-#{platform}-#{username}" 
  end

  def self.name_from_url(url)
    username_from_url(url, platform_from_url(url))
  end

  def self.description_from_url(url)
    "Supporting #{username_from_url(url, platform_from_url(url))} on #{platform_from_url(url).tr('-', ' ').titleize}"
  end

  def self.tags_from_url(url)
    platform = platform_from_url(url)
    ["funding", platform]
  end

  def self.username_from_url(url, platform)
    path_parts = URI.parse(url).path.split('/')
    case platform
    when 'github-sponsors'
      path_parts[2]
    when 'tidelift'
      path_parts.last
    else
      path_parts.reject(&:empty?).join('/')
    end
  end

  def self.platform_from_url(url)
    host = URI.parse(url).host
    host.include?('github') ? 'github-sponsors' : host.split('.').first
  end

  def self.create_by_website(url)
    # Define the mutation to create the project
    create_project_mutation = <<~GRAPHQL
      mutation CreateProject($parent: AccountReferenceInput!, $project: ProjectCreateInput!) {
        createProject(parent: $parent, project: $project) {
          id
          legacyId
          name
          description
          slug
          tags
          website
          imageUrl
          createdAt
          updatedAt
        }
      }
    GRAPHQL
  
    # Define the query to load the project by slug if needed
    load_project_query = <<~GRAPHQL
      query LoadProjectBySlug($slug: String!) {
        account(slug: $slug) {
          id
          legacyId
          name
        }
      }
    GRAPHQL
  
    # Set up variables for project creation
    project_slug = slug_from_url(url)
    variables = {
      parent: { slug: PROXY_PARENT_COLLECTIVE_SLUG },
      project: {
        name: name_from_url(url),
        slug: project_slug,
        description: description_from_url(url),
        tags: tags_from_url(url),
        # website: url # TOOD enable this once the website field is supported on OpenCollective.com
      }
    }
  
    # Send the createProject mutation
    payload = { query: create_project_mutation, variables: variables }.to_json
    response = Faraday.post(
      "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )
  
    puts "Response status: #{response.status}"
    puts "Response body: #{response.body}"
  
    response_data = JSON.parse(response.body)
  
    # Check for errors
    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
      
      # Check if the error is specifically about the slug being taken
      if response_data['errors'].any? { |error| error['message'].include?("slug '#{project_slug}' is already taken") }
        # If the slug is taken, attempt to load the existing project by slug
        load_payload = { query: load_project_query, variables: { slug: project_slug } }.to_json
        load_response = Faraday.post(
          "https://staging.opencollective.com/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
          load_payload,
          { 'Content-Type' => 'application/json' }
        )
        
        load_response_data = JSON.parse(load_response.body)
        if load_response_data['data'] && load_response_data['data']['account']
          project = load_response_data['data']['account']
          puts "Project with slug already exists. Loaded project ID: #{project['id']}"
          ProxyCollective.create(
            uuid: project['id'],
            legacy_id: project['legacyId'],
            slug: project['slug'],
            name: project['name'],
            description: project['description'],
            tags: project['tags'],
            website: project['website'] || url,
            image_url: project['imageUrl']
          )
        else
          puts "Error: Project exists but could not be loaded."
        end
      else
        # Handle other errors
        error_messages = response_data['errors'].map { |error| error['message'] }.join(', ')
        puts "Error creating project: #{error_messages}"
      end
    else
      # Project created successfully
      project = response_data['data']['createProject']
      puts "Project created: #{project['name']} (#{project['slug']})"
      ProxyCollective.create(
        uuid: project['id'],
        legacy_id: project['legacyId'],
        slug: project['slug'],
        name: project['name'],
        description: project['description'],
        tags: project['tags'],
        website: project['website'] || url,
        image_url: project['imageUrl']
      )
    end
  end
end
