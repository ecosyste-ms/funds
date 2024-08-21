class Allocation < ApplicationRecord
  belongs_to :fund
  has_many :project_allocations

  def calculate_funded_projects
    # get a list of all possible projects for this fund
    projects = find_possible_projects

    # Fetch all metrics for all projects
    metrics = projects.map do |project|
      {
        project_id: project.id,
        downloads: project.downloads || 0,
        stars: project.stars || 0,
        dependent_repos: project.dependent_repos_count || 0,
        dependent_packages: project.dependent_packages_count || 0,
      }
    end

    # normalize each metric across all projects
    normalized_metrics = normalize_metrics(metrics)

    # calculate weighted scores for each project
    total_score = 0
    scores = normalized_metrics.map do |metric|
      score = 0
  
      weights.each do |metric_name, weight|
        score += metric[metric_name] * weight
      end
  
      total_score += score
  
      { project_id: metric[:project_id], score: score }
    end

    # allocate funds proportionally to scores
    allocations = scores.map do |score|
      allocation_amount = (score[:score] / total_score) * total_cents
      { project_id: score[:project_id], allocation: allocation_amount, score: score[:score] }
    end

    # save the project allocations
    # TODO insert all allocations in a single transaction
    # TODO do we both to save allocations with a score of 0?
    allocations.each do |allocation|
      ProjectAllocation.create!(
        project_id: allocation[:project_id],
        allocation_id: self.id,
        fund_id: fund.id,
        amount_cents: allocation[:allocation],
        score: allocation[:score]
      )
    end
  end

  def weights
    # TODO these may need to be recorded in the database
    {
      dependent_repos: 0.2,
      dependent_packages: 0.2,
      downloads: 0.2,
      stars: 0.1,
    }
  end

  def normalize_metrics(metrics)
    # Initialize min and max for each metric
    mins = {}
    maxs = {}

    metrics.first.keys.each do |metric_name|
      next if metric_name == :project_id

      values = metrics.map { |m| m[metric_name] }
      mins[metric_name] = values.min
      maxs[metric_name] = values.max
    end

    # Normalize each metric to a scale between 0 and 1
    metrics.map do |metric|
      normalized = metric.dup

      normalized.each do |metric_name, value|
        next if metric_name == :project_id

        min = mins[metric_name]
        max = maxs[metric_name]
        normalized[metric_name] = (value - min).to_f / (max - min).to_f if max > min
      end

      normalized
    end
  end

  def find_possible_projects
    # TODO include aliases
    Project.keyword(fund.primary_topic)
  end

  def export_to_csv
    # TODO
  end

  def group_projects_by_funding_platform
    # TODO
  end
end
