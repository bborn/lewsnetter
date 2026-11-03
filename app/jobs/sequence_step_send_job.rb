# Sends one step of one enrollment. Every check runs right before the send,
# so a subscriber who unsubscribed, got suppressed or matched the exit
# segment since the last step gets nothing more.
class SequenceStepSendJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 3
  RETRY_DELAY = 1.hour
  # A claimed row is pushed this far out so the dispatcher leaves it alone
  # while we send. Overwritten by advance!/retry below.
  CLAIM_LEASE = 15.minutes

  def perform(enrollment_id, step_index)
    now = Time.current
    # Atomic claim: only the job that moves next_send_at wins, so the same
    # step never sends twice even if the dispatcher enqueued it twice.
    claimed = SequenceEnrollment
      .where(id: enrollment_id, state: "active", current_step: step_index)
      .where("next_send_at <= ?", now)
      .update_all(next_send_at: now + CLAIM_LEASE, updated_at: now)
    return if claimed.zero?

    enrollment = SequenceEnrollment.includes(:subscriber, sequence: :team).find(enrollment_id)
    sequence = enrollment.sequence
    subscriber = enrollment.subscriber

    # Paused or flag flipped off between dispatch and now: put it back.
    unless sequence.live?
      enrollment.update!(next_send_at: now)
      return
    end

    step = sequence.steps[step_index]
    return enrollment.advance!(at: now) if step.nil? # step deleted mid-flight

    # The column, not Mailkick's subscribed?(list) (opt-in, so always false here).
    return enrollment.exit!("unsubscribed", at: now) unless subscriber[:subscribed]
    if Suppression.for_team_emails(sequence.team, [subscriber.email.to_s.downcase]).any?
      return enrollment.suppress!(at: now)
    end
    if sequence.exit_segment && sequence.subscriber_in_segment?(sequence.exit_segment, subscriber)
      return enrollment.exit!("exit_segment", at: now)
    end
    if step.skip_segment && sequence.subscriber_in_segment?(step.skip_segment, subscriber)
      SequenceStep.where(id: step.id).update_counters(skipped_count: 1)
      return enrollment.advance!(at: now)
    end

    result = SesSender.send_bulk(campaign: step.campaign, subscribers: [subscriber])

    if result.suppressed.any?
      enrollment.suppress!(at: now)
    elsif result.failed.any?
      handle_failure(enrollment, result.failed.first[:error], now)
    else
      bump_last_contacted!(subscriber, now)
      enrollment.advance!(at: now)
    end
  end

  private

  def handle_failure(enrollment, error, now)
    attempts = enrollment.attempts + 1
    Rails.logger.warn("[SequenceStepSendJob] enrollment=#{enrollment.id} attempt=#{attempts}: #{error}")
    if attempts >= MAX_ATTEMPTS
      enrollment.update!(attempts: attempts)
      enrollment.exit!("send_failed", at: now)
    else
      enrollment.update!(attempts: attempts, next_send_at: now + RETRY_DELAY)
    end
  end

  def bump_last_contacted!(subscriber, now)
    Subscriber.where(id: subscriber.id).update_all(
      ["last_contacted_at = ?, times_contacted = COALESCE(times_contacted, 0) + 1", now]
    )
  end
end
