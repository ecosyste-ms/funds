# frozen_string_literal: true

funding_links = @project.funding_links
preferred_platform = @project.preferred_funding_platform
funding_source = @project.funding_source

# Selected funding destination: the stored funding source when one was
# recorded during sync, otherwise the preferred link derived from the known
# funding links. Deliberately not Project#preferred_funding_link, which may
# perform a live Open Collective mapping lookup; this endpoint only reads
# stored discovery results.
selected_link = funding_source&.url || funding_links.find { |link| link.include?(preferred_platform) }

# Discovered Open Collective destination, surfaced explicitly since it is not
# necessarily present in funding_links (found via Open Collective lookup or
# mapped from a GitHub Sponsors link and stored on the funding source).
open_collective_url = funding_source.url if funding_source&.platform == 'opencollective.com'

# A mapped alternative: an Open Collective destination stored for a project
# whose known links only include a GitHub Sponsors link.
has_sponsors_link = funding_links.any? { |link| link.include?('github.com/sponsors') }
open_collective_alternative = if has_sponsors_link && open_collective_url.present? && !funding_links.include?(open_collective_url)
  open_collective_url
else
  nil
end

json.name @project.to_s
json.repo_link @project.url
json.funding_links funding_links
json.preferred_funding_platform preferred_platform
json.preferred_funding_link selected_link
json.open_collective_match open_collective_url
json.open_collective_alternative open_collective_alternative
