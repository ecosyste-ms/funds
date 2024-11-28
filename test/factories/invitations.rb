FactoryBot.define do
  factory :invitation do
    association :project_allocation
    email { Faker::Internet.email }
    token { nil }

    # Traits for customizing the factory
    trait :with_custom_token do
      token { "custom_token_value" }
    end
  end
end