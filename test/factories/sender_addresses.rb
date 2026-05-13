FactoryBot.define do
  factory :sender_address do
    sequence(:email) { |n| "sender#{n}@example.com" }
    name { "Sender" }
    verified { false }
    ses_status { "unconfigured" }
    association :team
  end
end
