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
    # create on opencollective
    query = <<~GRAPHQL
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

    variables = {
      parent: { slug: PROXY_PARENT_COLLECTIVE_SLUG },
      project: {
        name: name_from_url(url),
        slug: slug_from_url(url),
        description: description_from_url(url),
        tags: tags_from_url(url),
        # website: url
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
      project = response_data['data']['createProject']
      puts "Project created: #{project['name']} (#{project['slug']})"
      ProxyCollective.create(
        uuid: project['id'],
        legacy_id: project['legacyId'],
        slug: project['slug'],
        name: project['name'],
        description: project['description'],
        tags: project['tags'],
        website: project['website'],
        image_url: project['imageUrl']
      )
    end
  end
end
