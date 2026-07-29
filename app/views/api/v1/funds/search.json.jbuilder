# frozen_string_literal: true

json.current_page @pagy.page
json.total_pages @pagy.pages

json.funds @funds do |fund|
  json.name fund.name
  json.html_url fund_url(fund)
  json.description fund.description
  json.total_donors fund.total_donors
end
