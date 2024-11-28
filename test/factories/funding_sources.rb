FactoryBot.define do
  factory :funding_source do
    url { Faker::Internet.url }
    platform { Faker::Lorem.word }
    current_balance_cents { Faker::Number.between(from: 1000, to: 100_000) }
    last_synced_at { Faker::Time.backward(days: 30) }
  end
end