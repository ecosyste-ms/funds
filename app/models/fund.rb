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
end
