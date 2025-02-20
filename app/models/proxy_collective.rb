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
    query = <<-GQL.strip
      mutation CreateVendor($vendor: VendorCreateInput!, $host: AccountReferenceInput!) {
        createVendor(vendor: $vendor, host: $host) {
          id
          legacyId
          slug
          type
          name
        }
      }
    GQL
  
    variables = {
      vendor: { name: url },
      host: { slug: 'opensource' }
    }
  
    payload = { query: query, variables: variables }.to_json
  
    connection = Faraday.new(url: "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}") do |faraday|
      faraday.request :multipart
      faraday.adapter Faraday.default_adapter
    end
  
    response = connection.post do |req|
      req.url "/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}"
      req.headers['Authorization'] = "Bearer #{ENV['OPENCOLLECTIVE_TOKEN']}"
      req.body = payload
      req.headers['Content-Type'] = 'application/json'
    end
  
    response_data = JSON.parse(response.body)
  
    if response_data['errors']
      puts "GraphQL Errors: #{response_data['errors']}"
      puts "Error creating vendor: #{response_data['errors'].map { |e| e['message'] }.join(', ')}"
      return nil
    else
      vendor = response_data['data']['createVendor']
      puts "Vendor created: #{vendor['name']} (#{vendor['slug']})"
      return ProxyCollective.create(
        uuid: vendor['id'],
        legacy_id: vendor['legacyId'],
        slug: vendor['slug'],
        name: vendor['name'],
        website: url
      )
    end
  end

  def platform
    self.class.platform_from_url(name)
  end

  def username
    self.class.username_from_url(name, platform)
  end

  def set_payout_method
    return if payout_method.present?
    
    query = <<-GRAPHQL
      mutation CreatePayoutMethod($payoutMethod: PayoutMethodInput!, $account: AccountReferenceInput!) {
        createPayoutMethod(payoutMethod: $payoutMethod, account: $account) {
          id
          type
          data
          isSaved
          name
        }
      }
    GRAPHQL

    payout_method_data = {
      type: "OTHER",
      isSaved: true,
      name: platform,
      data: {
        content: name,
        currency: "USD",
      }
    }

    variables = {
      payoutMethod: payout_method_data,
      account: { slug: slug }
    }

    payload = { query: query, variables: variables }.to_json

    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )

    response_body = JSON.parse(response.body)

    if response_body['errors']
      puts "Error creating payout method: #{response_body['errors']}"
      nil
    else
      payout_method = response_body['data']
      puts "Payout method created: #{payout_method}"
      update!(payout_method: payout_method)
    end
  end

  def destroy_vendor
    query = <<~GRAPHQL
      mutation DeleteAccount($account: AccountReferenceInput!) {
        deleteAccount(account: $account) {
          id
          slug
        }
      }
    GRAPHQL
  
    variables = {
      account: { id: uuid }
    }
  
    payload = { query: query, variables: variables }.to_json
  
    response = Faraday.post(
      "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/api/graphql/v2?personalToken=#{ENV['OPENCOLLECTIVE_TOKEN']}",
      payload,
      { 'Content-Type' => 'application/json' }
    )
  
    response_body = JSON.parse(response.body)
  
    if response_body['errors']
      puts "Error deleting vendor: #{response_body['errors']}"
      return nil
    else
      puts "Vendor deleted successfully: #{response_body['data']['deleteAccount']}"
      destroy # Delete the local record from the database
    end
  end
end
