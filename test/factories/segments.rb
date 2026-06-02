FactoryBot.define do
  factory :segment do
    sequence(:name) { |n| "Segment #{n}" }
    association :team
  end
end
