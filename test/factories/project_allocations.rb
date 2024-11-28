FactoryBot.define do
  factory :project_allocation do
    association :allocation
    association :project
    association :fund
    association :funding_source

    amount_cents { Faker::Number.between(from: 1000, to: 100_000) } # Random amount between $10 and $1000
    score { Faker::Number.decimal(l_digits: 1, r_digits: 2) } # Random score like 3.14
    created_at { Faker::Time.backward(days: 14) }
    updated_at { Faker::Time.backward(days: 7) }
  end
end