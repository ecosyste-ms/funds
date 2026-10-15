# frozen_string_literal: true

json.fund_name @fund.name
json.allocation_month_year @allocation.created_at.strftime('%B-%Y')
json.allocation_details do
  json.total_funded_amount do
    json.value @allocation.total_cents / 100.0
    json.currency 'USD'
  end
  json.funders_count @allocation.funders_count
  json.projects_count @allocation.funded_projects_count
end
json.distribution_details do
  json.open_collective_projects @allocation.open_collective_projects_count
  json.github_sponsored_projects @allocation.github_sponsored_projects_count
  json.other_projects @allocation.other_projects_count
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
json.funding_allocations @project_allocations do |allocation|
  json.project_name allocation.project.name
  json.project_repo_link allocation.project.url
  json.allocated_amount do
    json.value allocation.amount_cents / 100.0
    json.currency 'USD'
  end
  json.project_downloads allocation.project_downloads
  json.project_dependent_repos allocation.project_dependent_repos
  json.project_dependent_packages allocation.project_dependent_packages
  json.is_funding_rejected allocation.project_funding_rejected
  json.is_funding_allocation_success allocation.success?
  if allocation.funding_source.present?
    json.project_funding_source do
      json.url allocation.funding_source.url
      json.is_approved allocation.funding_source.approved?
    end
  else
    json.project_funding_source nil
  end
  if allocation.invitation.present?
    json.funding_invitation do
      json.invitation_accepted_at allocation.invitation.accepted_at
      json.invitation.rejected_at allocation.invitation.rejected_at
    end
  else
    json.funding_invitation nil
  end
end
