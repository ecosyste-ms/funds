# frozen_string_literal: true

json.fund_name @fund.name
json.allocation_month_year @allocation.created_at.strftime('%B-%Y')
json.allocation_details do
  if @allocation.completed?
    json.total_funded_amount do
      json.value @allocation.complete_payout_total_cents / 100.0
      json.currency 'USD'
    end
    json.funders_count @allocation.funders_count
    json.projects_count @allocation.complete_payout_projects_count
  else
    json.total_funded_amount do
      json.value @allocation.total_cents / 100.0
      json.currency 'USD'
    end
    json.funders_count @allocation.funders_count
    json.projects_count @allocation.funded_projects_count
  end
end
json.distribution_details do
  if @allocation.completed?
    json.github_sponsored_projects @allocation.completed_github_sponsored_projects_count
    json.open_collective_projects @allocation.completed_open_collective_projects_count
    json.other_projects @allocation.completed_other_projects_count
  else
    json.open_collective_projects @allocation.open_collective_projects_count
    json.github_sponsored_projects @allocation.github_sponsored_projects_count
    json.other_projects @allocation.other_projects_count
  end
  json.invited_projects @allocation.invited_projects_count
end
json.funders @allocation.funders do |funder|
  json.name funder[:name]
  json.total_funded do
    json.value funder[:amount]
    json.currency 'USD'
  end
  json.profile "https://#{ENV['OPENCOLLECTIVE_DOMAIN']}/#{funder[:slug]}"
end
json.funding_allocations @project_allocations do |pa|
  json.project_name pa.project.name
  json.project_repo_link pa.project.url
  json.allocated_amount do
    json.value pa.amount_cents / 100.0
    json.currency 'USD'
  end
  json.project_downloads pa.project_downloads
  json.project_dependent_repos pa.project_dependent_repos
  json.project_dependent_packages pa.project_dependent_packages
  json.is_funding_rejected pa.project_funding_rejected
  json.is_funding_allocation_success pa.success?
  if pa.funding_source.present?
    json.project_funding_source do
      json.url pa.funding_source.url
      json.is_approved pa.funding_source.approved?
    end
  else
    json.project_funding_source nil
  end
  if pa.invitation.present?
    json.funding_invitation do
      json.invitation_accepted_at pa.invitation.accepted_at
      json.invitation_rejected_at pa.invitation.rejected_at
    end
  else
    json.funding_invitation nil
  end
end
