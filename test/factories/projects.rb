FactoryBot.define do
  factory :project do
    name { Faker::App.name }
    url { Faker::Internet.url }
    description { Faker::Lorem.sentence }
    repository { {} }
    packages { [] }
    keywords { [] }
    last_synced_at { Faker::Time.backward(days: 30) }
  end
end