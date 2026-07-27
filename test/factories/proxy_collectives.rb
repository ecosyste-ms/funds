FactoryBot.define do
  factory :proxy_collective do
    uuid { SecureRandom.uuid }
    sequence(:slug) { |n| "esf-github-sponsors-#{Faker::Internet.slug}-#{n}" }
    name { Faker::Internet.username }
    description { Faker::Lorem.sentence }
    tags { ['funding', 'github-sponsors'] }
    website { Faker::Internet.url }
  end
end
