# Hourly (config/recurring.yml). For every live sequence:
#   - segment-triggered: enroll subscribers who now match the trigger segment
#   - any trigger: exit active enrollments whose subscriber now matches the
#     exit segment (SequenceStepSendJob re-checks this before each send too;
#     the sweep just stops them sooner and keeps the dashboard honest).
#   - any trigger: run step actions whose goal/click already happened, so a
#     subscriber who converts is tagged (and exited) within the hour rather
#     than when the next step comes due.
class SegmentEnrollmentSweepJob < ApplicationJob
  queue_as :default

  def perform
    Sequence.active.joins(:team).where(teams: {sequences_enabled: true}).find_each do |sequence|
      sweep_exits(sequence)
      sweep_actions(sequence)
      sweep_enrollments(sequence) if sequence.trigger_type == "segment"
    rescue Segment::InvalidPredicate => e
      Rails.logger.warn("[SegmentEnrollmentSweepJob] sequence=#{sequence.id}: #{e.message}")
    end
  end

  private

  def sweep_enrollments(sequence)
    segment = sequence.trigger_segment
    return if segment.nil? || sequence.steps.empty?

    candidates = segment.applies_to(sequence.team.subscribers.subscribed)
      .where.not(id: sequence.enrollments.active.select(:subscriber_id))
    # Without re-entry nobody enrolls twice, so skip anyone with history in SQL
    # instead of loading them just to have enroll! turn them away.
    if sequence.reentry_days.nil?
      candidates = candidates.where.not(id: sequence.enrollments.select(:subscriber_id))
    end
    if sequence.excluded_sequence_ids.present?
      candidates = candidates.where.not(
        id: SequenceEnrollment.where(sequence_id: sequence.excluded_sequence_ids).select(:subscriber_id)
      )
    end

    candidates.find_each { |subscriber| sequence.enroll!(subscriber) }
  end

  def sweep_actions(sequence)
    sequence.enrollments.active.where.not(pending_action_step: nil)
      .includes(:subscriber).find_each do |enrollment|
        enrollment.resolve_pending_action!(final: false)
      end
  end

  def sweep_exits(sequence)
    segment = sequence.exit_segment
    return if segment.nil?

    matching = segment.applies_to(sequence.team.subscribers).select(:id)
    sequence.enrollments.active.where(subscriber_id: matching).find_each do |enrollment|
      enrollment.exit!("exit_segment")
    end
  end
end
