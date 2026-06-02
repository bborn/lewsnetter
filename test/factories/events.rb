FactoryBot.define do
  factory :event do
    sequence(:name) { |n| "event.#{n}" }
    occurred_at { Time.current }
    properties { {} }
    association :subscriber
    # Derive team from subscriber so cross-team isolation tests don't trip on
    # a mismatched auto-created team. Callers can still pass team: explicitly.
    team { subscriber.team }
  end
end
