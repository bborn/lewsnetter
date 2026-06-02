FactoryBot.define do
  factory :campaign do
    sequence(:subject) { |n| "Campaign #{n}" }
    body_markdown { "Hello, world." }
    status { "draft" }
    association :team
  end
end
