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
  def advance!(at: Time.current)
    next_index = current_step + 1
    next_step = sequence.steps[next_index]
    if next_step
      update!(current_step: next_index, attempts: 0,
        next_send_at: at + next_step.delay_minutes.minutes)
    else
      update!(current_step: next_index, attempts: 0, state: "completed",
        completed_at: at, next_send_at: nil)
    end
  end
end
