# frozen_string_literal: true

json.name @project.to_s
json.repo_link @project.url
json.funding_links @project.funding_links
json.preferred_funding_platform @project.stored_preferred_funding_platform
json.preferred_funding_link @project.stored_preferred_funding_link
json.open_collective_match @project.open_collective_match
json.open_collective_alternative @project.open_collective_alternative
