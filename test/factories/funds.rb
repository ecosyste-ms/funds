FactoryBot.define do
  factory :fund do
    sequence(:name) { |n| "#{Faker::Company.name} #{n}" }
    sequence(:slug) { |n| "#{Faker::Internet.slug}-#{n}" }
    primary_topic { Faker::Lorem.word }
    secondary_topics { [] }
    description { Faker::Lorem.sentence }
    projects_count { 0 }
    balance { Faker::Number.decimal(l_digits: 2) }
  end
end