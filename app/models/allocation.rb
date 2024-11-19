class Allocation < ApplicationRecord
  belongs_to :fund
  has_many :project_allocations, dependent: :destroy
  has_many :projects, through: :project_allocations
  has_many :funding_sources, through: :project_allocations

  scope :displayable, -> { where('funded_projects_count > 0') }

  def to_s
    name
  end

  def name
    created_at.strftime('%Y-%m')
  end

  def calculate_funded_projects
    # TODO: Only calculate if the fund has over a certain amount of money
  
    weights = (read_attribute(:weights) || default_weights).symbolize_keys
    minimum_allocation = read_attribute(:minimum_allocation) || default_minimum_allocation

    # Get a list of all possible projects for this fund
    projects = find_possible_projects
  
    if projects.empty?
      puts "No projects found for fund #{fund.id}"
      return false
    end

    # Fetch all metrics for all projects
    metrics = projects.map do |project|
      {
        project_id: project.id,
        downloads: project.downloads(fund.registry_name) || 0,
        dependent_repos: project.dependent_repos_count(fund.registry_name) || 0,
        dependent_packages: project.dependent_packages_count(fund.registry_name) || 0,
        funding_source_id: project.funding_source_id
      }
    end
  
    # Normalize metrics and explicitly return max values
    normalized_metrics, maxs = normalize_metrics_with_max_storage(metrics)
  
    # Calculate weighted scores for each project
    total_score = 0
    scores = normalized_metrics.map do |metric|
      score = weights.sum { |metric_name, weight| metric[metric_name] * weight }
      total_score += score
      { project_id: metric[:project_id], score: score, funding_source_id: metric[:funding_source_id] }
    end
  
    # Initial allocation calculation
    allocations = []
    leftover_funds = 0
  
    scores.each do |score|
      allocation_amount = (score[:score] / total_score) * total_cents
  
      if allocation_amount < minimum_allocation
        leftover_funds += allocation_amount
      else
        allocations << { project_id: score[:project_id], allocation: allocation_amount, score: score[:score], funding_source_id: score[:funding_source_id] }
      end
    end
  
    # Redistribute leftover funds
    total_remaining_score = allocations.sum { |a| a[:score] }
    allocations.each do |allocation|
      additional_amount = (allocation[:score] / total_remaining_score) * leftover_funds
      allocation[:allocation] += additional_amount
    end
  
    # Save allocations meeting the minimum allocation
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
  
    # Store the maxs and weights used for this allocation
    update!(max_values: maxs, weights: weights, minimum_allocation_cents: minimum_allocation, funded_projects_count: project_allocations.count)
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
    1 # TODO
  end

  def find_possible_projects
    fund.possible_projects.active.with_license
  end

  def export_to_csv
    # TODO
  end

  def group_projects_by_funding_source_and_platform
    project_allocations.order('amount_cents desc').includes(:funding_source).with_funding_source
                      .group_by { |pa| [pa.funding_source.platform, pa.funding_source] }
                       .transform_values { |pas| pas.sum(&:amount_cents) }
                       .sort_by { |platform, amount| -amount }
  end

  def payout
    project_allocations.find_each(&:choose_payout_method)
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
    project_allocations.select{|pa| pa.funding_source.blank?}.length
  end

  def github_sponsors_csv_export
    CSV.generate do |csv|
      csv << ['Maintainer username', 'Sponsorship amount in USD']
      project_allocations.select{|pa| pa.funding_source && pa.funding_source.platform == 'github.com'}.each do |pa|
        csv << [pa.funding_source.name, pa.amount_cents / 100.0]
      end
    end
  end
end
