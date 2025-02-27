class Allocation < ApplicationRecord
  belongs_to :fund
  has_many :project_allocations, dependent: :destroy
  has_many :projects, through: :project_allocations
  has_many :funding_sources, through: :project_allocations

  scope :displayable, -> { where('funded_projects_count > 0') }
  scope :completed, -> { where.not(completed_at: nil) }

  def to_s
    name
  end

  def name
    created_at.strftime('%Y-%m')
  end

  def completed?
    completed_at.present?
  end

  def complete!
    update!(completed_at: Time.now)
  end

  def calculate_funded_projects
    # TODO: Only calculate if the fund has over a certain amount of money
  
    projects = find_possible_projects
    return false if projects.empty?
  
    weights = (read_attribute(:weights) || default_weights).symbolize_keys
    minimum_allocation = read_attribute(:minimum_allocation) || default_minimum_allocation
  
    normalized_metrics, maxs = fetch_project_metrics(projects)
    scores, total_score = calculate_scores(normalized_metrics, weights)
  
    allocations = total_score.zero? ? allocate_funds_evenly(scores) : allocate_funds_by_score(scores, total_score)
  
    distribute_leftover_funds(allocations) unless total_score.zero?
  
    save_project_allocations(allocations, minimum_allocation, maxs, weights)
  end
  
  def fetch_project_metrics(projects)
    metrics = projects.map do |project|
      {
        project_id: project.id,
        downloads: project.downloads(fund.registry_name) || 0,
        dependent_repos: project.dependent_repos_count(fund.registry_name) || 0,
        dependent_packages: project.dependent_packages_count(fund.registry_name) || 0,
        funding_source_id: project.funding_source_id
      }
    end
  
    normalize_metrics_with_max_storage(metrics)
  end
  
  def calculate_scores(normalized_metrics, weights)
    total_score = 0
  
    scores = normalized_metrics.map do |metric|
      score = weights.sum { |metric_name, weight| metric[metric_name] * weight }
      total_score += score
      { project_id: metric[:project_id], score: score, funding_source_id: metric[:funding_source_id] }
    end
  
    # Sort to ensure deterministic allocation
    scores.sort_by! { |s| s[:project_id] }
  
    [scores, total_score]
  end
  
  def allocate_funds_evenly(scores)
    allocation_amount = total_cents / scores.size
  
    scores.map do |score|
      { project_id: score[:project_id], allocation: allocation_amount, score: score[:score], funding_source_id: score[:funding_source_id] }
    end
  end
  
  def allocate_funds_by_score(scores, total_score)
    allocations = []
    total_allocated = 0
    leftover_funds = 0
  
    scores.each do |score|
      allocation_amount = (score[:score] * total_cents) / total_score
      allocation_amount = (allocation_amount / 100) * 100 # Round to whole dollars
      total_allocated += allocation_amount
  
      if allocation_amount < default_minimum_allocation
        leftover_funds += allocation_amount
      else
        allocations << { project_id: score[:project_id], allocation: allocation_amount, score: score[:score], funding_source_id: score[:funding_source_id] }
      end
    end
  
    [allocations, total_allocated, leftover_funds]
  end
  
  def distribute_leftover_funds(allocations)
    total_allocated = allocations.sum { |a| a[:allocation] }
    leftover = total_cents - total_allocated
  
    allocations.first[:allocation] += leftover if leftover.positive?
  end
  
  def save_project_allocations(allocations, minimum_allocation, maxs, weights)
    allocations.each do |allocation|
      next if allocation[:allocation] < minimum_allocation
  
      ProjectAllocation.create!(
        project_id: allocation[:project_id],
        allocation_id: self.id,
        fund_id: fund.id,
        funding_source_id: allocation[:funding_source_id],
        amount_cents: allocation[:allocation],
        score: allocation[:score]
      )
    end
  
    update!(
      max_values: maxs,
      weights: weights,
      minimum_allocation_cents: minimum_allocation,
      funded_projects_count: project_allocations.count
    )
  end

  def normalize_metrics_with_max_storage(metrics)
    maxs = {}

    # Calculate and store the max values for each metric
    metrics.first.keys.each do |metric_name|
      next if metric_name == :project_id
      next if metric_name == :funding_source_id

      values = metrics.map { |m| m[metric_name] }
      maxs[metric_name] = values.max
    end

    # Normalize using zero as min and store the maxs
    normalized_metrics = metrics.map do |metric|
      normalized = metric.dup
      normalized.each do |metric_name, value|
        next if metric_name == :project_id
        next if metric_name == :funding_source_id

        max = maxs[metric_name]
        normalized[metric_name] = (value.to_f / max) if max > 0
      end
      normalized
    end

    # Return both the normalized metrics and the maxs
    return normalized_metrics, maxs
  end

  def default_minimum_allocation
    50_00 # cents
  end

  def default_weights
    {
      dependent_repos: 0.2,
      dependent_packages: 0.2,
      downloads: 0.2
    }
  end

  def total_allocated_cents
    project_allocations.sum(:amount_cents)
  end

  def funders_count
    funders.length
  end

  def find_possible_projects
    fund.possible_projects.active.with_license
  end

  def export_to_csv
    # TODO
  end

  def group_projects_by_funding_source_and_platform
    project_allocations.order('amount_cents desc').includes(:funding_source).with_approved_funding_source
                      .group_by { |pa| [pa.funding_source.platform, pa.funding_source] }
                       .transform_values { |pas| pas.sum(&:amount_cents) }
                       .sort_by { |platform, amount| -amount }
  end

  def payout
    project_allocations.each(&:payout)
  end

  def payout_open_source_collectives
    project_allocations.select(&:is_osc_collective?).each(&:payout)
  end

  def payout_open_collectives
    project_allocations.select(&:is_non_osc_collective?).each(&:payout)
  end

  def payout_proxy_collectives
    project_allocations.select(&:is_proxy_collective?).each(&:payout)
  end

  def payout_invited
    project_allocations.select(&:is_invited?).each(&:payout)
  end

  def github_sponsored_projects_count
    funding_sources.select{|fs| fs.platform == 'github.com'}.length
  end

  def open_collective_projects_count
    funding_sources.select{|fs| fs.platform == 'opencollective.com'}.length
  end

  def other_projects_count
    funding_sources.approved.reject{|fs| ['opencollective.com', 'github.com'].include?(fs.platform) }.length
  end

  def invited_projects_count
    project_allocations.includes(:funding_source).select{|pa| pa.funding_source.blank?}.length
  end

  def github_sponsors_csv_export
    CSV.generate do |csv|
      csv << ['Maintainer username', 'Sponsorship amount in USD']
      
      grouped_allocations = project_allocations
        .select { |pa| pa.funding_source && pa.funding_source.platform == 'github.com' }
        .group_by { |pa| pa.funding_source.name }
        .transform_values { |pas| pas.sum { |pa| pa.amount_cents } }
        .sort_by { |_, amount_cents| -amount_cents } # Sort by amount descending
    
      grouped_allocations.each do |maintainer, amount_cents|
        csv << [maintainer, amount_cents / 100.0]
      end
    end
  end

  def self.github_sponsors_csv_export(allocations)
    CSV.generate do |csv|
      csv << ['Maintainer username', 'Sponsorship amount in USD']
  
      grouped_allocations = allocations.flat_map(&:project_allocations)
        .select { |pa| pa.funding_source&.platform == 'github.com' }
        .group_by { |pa| pa.funding_source.name }
        .transform_values { |pas| pas.sum(&:amount_cents) }
        .sort_by { |_, amount_cents| -amount_cents } # Sort by amount descending
  
      grouped_allocations.each do |maintainer, amount_cents|
        csv << [maintainer, amount_cents / 100.0]
      end
    end
  end

  def transaction_start_date
    created_at - 1.month
  end

  def transaction_end_date
    created_at
  end

  def funder_names
    all_names = fund.transactions.donations.between(transaction_start_date, transaction_end_date).distinct.pluck(:account_name)
    return 'Funders' if all_names.empty?
    if all_names.length == 1
      all_names.first
    elsif all_names.length < 6
      all_names[0..-2].join(', ') + ' and ' + all_names.last
    else
      all_names[0..4].join(', ') + ' and ' + (all_names.length - 5).to_s + ' more'
    end
  end

  def funders
    fund.transactions.donations.between(transaction_start_date, transaction_end_date).map{|t| {name: t.account_name, slug: t.account, image_url: t.account_image_url, amount: t.amount}}
      .group_by { |t| t[:slug] }
      .map { |slug, txns| { slug: slug, name: txns.first[:name], image_url: txns.first[:image_url], amount: txns.sum { |t| t[:amount] } } }
      .sort_by { |f| -f[:amount] }
  end

  def decline_deadline
    created_at + 14.days
  end
  
  def send_invitations
    project_allocations.select{|pa| pa.funding_source.blank?}.each do |pa|
      pa.send_invitation
    end
  end

  
end
