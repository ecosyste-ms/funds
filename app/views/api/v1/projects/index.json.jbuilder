# frozen_string_literal: true

json.fund_name @fund.name
json.projects_count @fund.possible_projects_count
json.funded_projects_count @fund.funded_projects_count
json.completed_allocations_total do
  json.value @fund.completed_allocations_total
  json.currency 'USD'
end
json.current_page @pagy.page
json.total_pages @pagy.pages

json.projects @projects do |project|
  json.name project.to_s
  json.repo_link project.url
  json.allocated_amount do
    json.value(project.total_allocated / 100)
    json.currency 'USD'
  end
  json.downloads project.total_downloads
  json.dependent_repos project.total_dependent_repos
  json.dependent_packages project.total_dependent_packages
end
