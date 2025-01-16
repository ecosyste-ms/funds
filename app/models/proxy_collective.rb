class ProxyCollective < ApplicationRecord

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
    else
      path_parts.reject(&:empty?).join('/')
    end
  end

  def self.image_url_from_url(url)
    case platform_from_url(url)
    when 'github-sponsors'
      "https://github.com/#{username_from_url(url, 'github-sponsors')}.png"
    else
      "https://github.com/ecosyste-ms.png"
    end
  end

  def self.platform_from_url(url)
    host = URI.parse(url).host
    host.include?('github') ? 'github-sponsors' : host.split('.').first
  end

  def self.create_by_website(url)
    file = download_image(image_url_from_url(url))
    return unless file
  
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
  
    load_project_query = <<~GRAPHQL
      query LoadProjectBySlug($slug: String!) {
        account(slug: $slug) {
          id
          legacyId
          name
        }
      }
    GRAPHQL
  
    project_slug = slug_from_url(url)
    operations = {
      query: create_project_mutation,
      variables: {
        parent: { slug: ENV['PROXY_PARENT_COLLECTIVE_SLUG'] },
        project: {
          name: name_from_url(url),
          slug: project_slug,
          description: description_from_url(url),
          tags: tags_from_url(url),
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
      
      # Check if the error is specifically about the slug being taken
      if response_data['errors'].any? { |error| error['message'].include?("slug '#{project_slug}' is already taken") }
        # If the slug is taken, attempt to load the existing project by slug
        load_payload = { query: load_project_query, variables: { slug: project_slug } }.to_json
        load_response = Faraday.post(
          "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
          load_payload,
          { 'Content-Type' => 'application/json' }
        )
        
        load_response_data = JSON.parse(load_response.body)
        if load_response_data['data'] && load_response_data['data']['account']
          project = load_response_data['data']['account']
          puts "Project with slug already exists. Loaded project ID: #{project['id']}"
          pc = ProxyCollective.create(
            uuid: project['id'],
            legacy_id: project['legacyId'],
            slug: project['slug'],
            name: project['name'],
            description: project['description'],
            tags: project['tags'],
            website: project['website'] || url,
            image_url: project['imageUrl']
          )
          pc.update_social_links
        else
          puts "Error: Project exists but could not be loaded."
        end
      else
        error_messages = response_data['errors'].map { |error| error['message'] }.join(', ')
        puts "Error creating project: #{error_messages}"
      end
    else
      project = response_data['data']['createProject']
      puts "Project created: #{project['name']} (#{project['slug']})"
      pc = ProxyCollective.create(
        uuid: project['id'],
        legacy_id: project['legacyId'],
        slug: project['slug'],
        name: project['name'],
        description: project['description'],
        tags: project['tags'],
        website: project['website'] || url,
        image_url: project['imageUrl']
      )
      pc.update_social_links
    end
  ensure
    file.close if file
    file.unlink if file
  end
  
  def self.download_image(url)
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
      account: { slug: slug },
      socialLinks: [
        { type: "WEBSITE", url: website }
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

  def enable_contributions
    # TODO once we have the ability to enable contributions on opencollective
  end

  def disable_contributions
    # TODO once we have the ability to disable contributions on opencollective
  end
end
