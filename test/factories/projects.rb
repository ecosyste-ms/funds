FactoryBot.define do
  factory :project do
    name { Faker::App.name }
    sequence(:url) { |n| "https://github.com/#{Faker::Internet.slug}/#{Faker::Internet.slug}-#{n}" }
    description { Faker::Lorem.sentence }
    repository { {} }
    packages { [] }
    keywords { [] }
    last_synced_at { Faker::Time.backward(days: 30) }
  end
end