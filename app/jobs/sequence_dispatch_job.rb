# Every minute (config/recurring.yml): hand each due enrollment to
# SequenceStepSendJob. The send job claims the row itself, so a double
# dispatch (overlapping ticks) can't double-send.
class SequenceDispatchJob < ApplicationJob
  queue_as :default

  BATCH_LIMIT = 5_000

  def perform(now: Time.current)
    SequenceEnrollment.due(now)
      .joins(sequence: :team)
      .where(sequences: {status: "active"}, teams: {sequences_enabled: true})
      .order(:next_send_at)
      .limit(BATCH_LIMIT)
      .pluck(:id, :current_step)
      .each { |id, step| SequenceStepSendJob.perform_later(id, step) }
  end
end
