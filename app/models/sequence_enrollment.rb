# A subscriber's trip through a Sequence. `current_step` is the 0-based index
# of the next step due and `next_send_at` is when. SequenceDispatchJob picks
# up due rows; SequenceStepSendJob claims, checks and sends one step.
class SequenceEnrollment < ApplicationRecord
  STATES = %w[active completed exited suppressed].freeze

  belongs_to :sequence
  belongs_to :subscriber

  scope :active, -> { where(state: "active") }
  scope :due, ->(now = Time.current) { active.where("next_send_at <= ?", now) }

  validates :state, inclusion: {in: STATES}

  STATES.each do |s|
    define_method("#{s}?") { state == s }
  end

  def exit!(reason, at: Time.current)
    update!(state: "exited", exit_reason: reason, exited_at: at, next_send_at: nil)
  end

  def suppress!(at: Time.current)
    update!(state: "suppressed", exit_reason: "suppressed", exited_at: at, next_send_at: nil)
  end

  # Move past the step at `current_step`: schedule the next one, or finish.
  # With finish_after_minutes set, the last step is followed by one more
  # wait (current_step == steps.size) so its action still has time to fire
  # before the enrollment completes.
  def advance!(at: Time.current)
    next_index = current_step + 1
    step_count = sequence.steps.size
    if (next_step = sequence.steps[next_index])
      update!(current_step: next_index, attempts: 0,
        next_send_at: at + next_step.delay_minutes.minutes)
    elsif next_index == step_count && sequence.finish_after_minutes.positive?
      update!(current_step: next_index, attempts: 0,
        next_send_at: at + sequence.finish_after_minutes.minutes)
    else
      complete!(at: at)
    end
  end

  def complete!(at: Time.current)
    update!(current_step: [current_step, sequence.steps.size].max, attempts: 0,
      state: "completed", completed_at: at, next_send_at: nil)
    subscriber.add_tag!(sequence.completed_tag) if sequence.completed_tag.present?
  end

  # Called after a step sends: its action (if any) waits from now.
  def await_action!(step, index, at: Time.current)
    if step.action?
      update!(pending_action_step: index, pending_action_since: at)
    elsif pending_action_step
      update!(pending_action_step: nil, pending_action_since: nil)
    end
  end

  # Runs the pending step action, if it fired: tag, then exit when the
  # action says so. Returns true when the enrollment exited. `final` is the
  # last look (the next step is due): the action is cleared either way. The
  # hourly sweep looks early with final: false, which leaves an unfired
  # action waiting.
  def resolve_pending_action!(at: Time.current, final: true)
    return false if pending_action_step.nil?
    step = sequence.steps[pending_action_step]
    fired = step&.action? && step.action_fired?(subscriber, since: pending_action_since)
    return false if !fired && !final
    update!(pending_action_step: nil, pending_action_since: nil)
    return false unless fired

    subscriber.add_tag!(step.action_tag) if step.action_tag
    return false unless step.action_exit
    exit!((step.action_trigger == "goal") ? "goal" : "clicked", at: at)
    true
  end
end
