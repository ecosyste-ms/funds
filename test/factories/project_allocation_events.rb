FactoryBot.define do
  factory :project_allocation_event do
    association :project_allocation
    association :fund
    association :allocation
    event_type { 'payout_started' }
    status { 'success' }
    message { nil }
    metadata { {} }
  end
end
