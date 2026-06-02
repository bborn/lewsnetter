FactoryBot.define do
  factory :subscriber do
    sequence(:email) { |n| "subscriber#{n}@example.com" }
    sequence(:external_id) { |n| "ext-#{n}" }
    name { "Subscriber" }
    subscribed { true }
    association :team
  end
end
