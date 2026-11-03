# Enrolls an Event's subscriber into every live sequence of the team that
# triggers on that event name. Enqueued by Event#after_create_commit.
class EnrollOnEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.find_by(id: event_id)
    return if event.nil?

    team = event.team
    return unless team.sequences_enabled?

    team.sequences.active.event_triggered(event.name).find_each do |sequence|
      sequence.enroll!(event.subscriber)
    end
  end
end
