FactoryBot.define do
  factory :fund do
    name { Faker::Company.name }
    slug { Faker::Internet.slug }
    primary_topic { Faker::Lorem.word }
    secondary_topics { [] }
    description { Faker::Lorem.sentence }
    projects_count { 0 }
    balance { Faker::Number.decimal(l_digits: 2) }
  end
end