module SequencesHelper
  # "Immediately", "Wait 3 days", "Wait 1 hour".
  def sequence_step_delay_label(step)
    return "Immediately" if step.delay_minutes.to_i.zero?
    "Wait #{pluralize(step.delay_amount, step.delay_unit.singularize)}"
  end

  def sequence_reentry_label(sequence)
    return "Once per subscriber" if sequence.reentry_days.nil?
    "Again after #{pluralize(sequence.reentry_days, "day")}"
  end
end
