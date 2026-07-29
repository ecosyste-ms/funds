# frozen_string_literal: true

json.projects_count @fund.possible_projects_count
json.project_downloads @fund.funded_project_downloads
json.project_dependent_repos @fund.funded_project_dependent_repos
json.project_dependent_packages @fund.funded_project_dependent_packages

json.total_donation_amount do
  json.value @fund.total_donation_amount
  json.currency 'USD'
end

json.total_donors @fund.total_donors

json.funded_projects_count @fund.funded_projects_count

json.completed_allocations_count @fund.allocations.completed.count

json.completed_allocations_total do
  json.value @fund.completed_allocations_total
  json.currency 'USD'
end

json.top_3_funders @fund.funders.first(3) do |funder|
  json.funder_name funder[:name]

  json.funder_amount do
    json.value funder[:amount]
    json.currency 'USD'
  end

  json.funder_link "https://opencollective.com/#{funder[:slug]}"
end
