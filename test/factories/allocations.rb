FactoryBot.define do
  factory :allocation do
    association :fund
    year { Time.current.year }
    month { Faker::Number.between(from: 1, to: 12) }
    total_cents { Faker::Number.between(from: 10_000, to: 1_000_000) }
    funded_projects_count { Faker::Number.between(from: 1, to: 100) }
    max_values { {} }
    weights { {} }
    minimum_allocation_cents { 1000 }
  end
end