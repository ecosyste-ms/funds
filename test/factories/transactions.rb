FactoryBot.define do
  factory :transaction do
    association :fund
    sequence(:uuid) { |n| "#{SecureRandom.uuid}-#{n}" }
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    net_amount { amount }
    transaction_type { 'CREDIT' }
    transaction_kind { 'CONTRIBUTION' }
    currency { 'USD' }
    account { Faker::Internet.slug }
    account_name { Faker::Company.name }
    description { Faker::Lorem.sentence }
    order { { 'legacyId' => Faker::Number.number(digits: 6) } }
  end
end
