FactoryBot.define do
  factory :sequence do
    association :team, sequences_enabled: true
    sequence(:name) { |n| "Onboarding #{n}" }
    status { "draft" }
    trigger_type { "event" }
    trigger_event_name { "signed_up" }

    trait :live do
      status { "active" }
      sender_address { association(:sender_address, team: team, verified: true, ses_status: "verified") }
    end
  end

  factory :sequence_step do
    association :sequence
    delay_minutes { 0 }
    sequence(:subject) { |n| "Step #{n}" }
    body_markdown { "Hi {{subscriber.name}}, welcome aboard." }
  end
end
