module SequencesHelper
  # "Immediately", "Wait 3 days", "Wait 1 hour".
  def sequence_step_delay_label(step)
    return "Immediately" if step.delay_minutes.to_i.zero?
    "Wait #{pluralize(step.delay_amount, step.delay_unit.singularize)}"
  end

  # "On goal: tag Connected Accts, exit". Nil when the step has no action.
  def sequence_step_action_label(step)
    return unless step.action?
    outcomes = []
    outcomes << "tag #{step.action_tag}" if step.action_tag.present?
    outcomes << "exit" if step.action_exit?
    "On #{step.action_trigger}: #{outcomes.join(", ")}"
  end

  def sequence_goal_label(sequence)
    parts = []
    parts << sequence.goal_segment.name if sequence.goal_segment
    parts << sequence.goal_event_name if sequence.goal_event_name.present?
    parts.any? ? parts.join(" or ") : "—"
  end

  def sequence_finish_label(sequence)
    wait = sequence.finish_after_minutes.to_i
    tag = sequence.completed_tag.presence
    return "Ends after last step" if wait.zero? && tag.nil?
    parts = []
    parts << "Wait #{pluralize(sequence.finish_after_days, "day")}" if wait.positive?
    parts << "tag #{tag}" if tag
    parts.join(", then ")
  end

  def sequence_reentry_label(sequence)
    return "Once per subscriber" if sequence.reentry_days.nil?
    "Again after #{pluralize(sequence.reentry_days, "day")}"
  end
end
