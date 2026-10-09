# frozen_string_literal: true

json.fund_name @fund.name
json.total_funders_count @fund.funders.length
json.repeat_funders_count @fund.repeat_funders.length
json.one_time_funders_count @fund.single_funders.length
json.current_page @pagy.page
json.total_pages @pagy.pages

json.funders @funders do |funder|
  json.funder_name funder[:name]
  json.total_funded do
    json.value funder[:amount]
    json.currency 'USD'
  end
  json.donations_count funder[:donations_count]
  json.profile "https://opencollective.com/#{funder[:slug]}"
end
