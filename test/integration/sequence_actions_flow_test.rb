require "controllers/api/v1/test"

# Step actions (goal hit / link clicked → tag and/or exit), the finish wait,
# completion and sent tags, tag segments, and "not enrolled in sequence X".
# Real models and jobs throughout; only SES is stubbed.
class SequenceActionsFlowTest < Api::V1::Test
  include ActiveJob::TestHelper

  BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"

  setup do
    @team.update!(sequences_enabled: true)
    @sender = @team.sender_addresses.create!(
      email: "hello@example.com", name: "Hello", verified: true, ses_status: "verified"
    )
    @sequence = @team.sequences.create!(
      name: "Connect accounts", status: "active", trigger_type: "event",
      trigger_event_name: "signed_up", sender_address: @sender,
      goal_event_name: "account:connected"
    )
    @step1 = @sequence.steps.create!(delay_minutes: 0, subject: "Connect", body_markdown: "Go",
      action_trigger: "goal", action_tag: "Connected", action_exit: true, sent_tag: "Got email 1")
    @step2 = @sequence.steps.create!(delay_minutes: 3.days.in_minutes.to_i, subject: "Reminder",
      body_markdown: "Still there?", action_trigger: "goal", action_tag: "Connected", action_exit: true)

    @original_ses = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
  end

  teardown do
    Rails.application.config.ses_client = @original_ses
  end

  test "hitting the goal after a step tags and exits before the next step" do
    subscriber = enroll!
    tick!
    assert_equal [@step1.id], sent_step_ids(subscriber)
    assert_equal ["Got email 1"], subscriber.reload.tags
    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal 0, enrollment.pending_action_step

    travel 1.day do
      track!("account:connected")
    end
    travel 3.days + 1.minute do
      tick!
    end

    assert_equal [@step1.id], sent_step_ids(subscriber), "the reminder must not go out"
    enrollment.reload
    assert_equal "exited", enrollment.state
    assert_equal "goal", enrollment.exit_reason
    assert_equal ["Got email 1", "Connected"], subscriber.reload.tags
  end

  test "a goal event from before the step was sent doesn't count" do
    track!("account:connected")
    subscriber = enroll!
    tick!

    travel 3.days + 1.minute do
      tick!
    end
    assert_equal [@step1.id, @step2.id], sent_step_ids(subscriber)
    assert_not_includes subscriber.reload.tags, "Connected"
  end

  test "the hourly sweep runs a fired action without waiting for the next step" do
    subscriber = enroll!
    tick!
    travel 2.hours do
      track!("account:connected")
      SegmentEnrollmentSweepJob.perform_now
    end

    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal "exited", enrollment.state
    assert_includes subscriber.reload.tags, "Connected"
  end

  test "the sweep leaves an unfired action waiting" do
    subscriber = enroll!
    tick!
    SegmentEnrollmentSweepJob.perform_now

    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal "active", enrollment.state
    assert_equal 0, enrollment.pending_action_step
  end

  test "a goal segment counts as the goal too" do
    @sequence.update!(goal_event_name: nil, goal_segment: plan_segment("paid"))
    subscriber = enroll!
    tick!
    subscriber.update!(custom_attributes: {"plan" => "paid"})

    travel 3.days + 1.minute do
      tick!
    end
    assert_equal [@step1.id], sent_step_ids(subscriber)
    assert_equal "goal", @sequence.enrollments.find_by!(subscriber: subscriber).exit_reason
  end

  test "a click action tags without exiting when exit is off" do
    @step1.update!(action_trigger: "click", action_tag: "Clicked email 1", action_exit: false)
    subscriber = enroll!
    tick!
    travel 1.hour do
      ClickEvent.record!(delivery: subscriber.deliveries.last, url: "https://example.com/connect",
        user_agent: BROWSER_UA, ip: "203.0.113.9", http_method: "GET")
    end

    travel 3.days + 1.minute do
      tick!
    end
    assert_equal [@step1.id, @step2.id], sent_step_ids(subscriber)
    assert_includes subscriber.reload.tags, "Clicked email 1"
    assert_equal 1, @sequence.enrollments.find_by!(subscriber: subscriber).pending_action_step,
      "step 2's own action is now the one waiting"
  end

  test "a bot click doesn't fire a click action" do
    @step1.update!(action_trigger: "click", action_tag: "Clicked email 1", action_exit: true)
    subscriber = enroll!
    tick!
    ClickEvent.record!(delivery: subscriber.deliveries.last, url: "https://example.com/connect",
      user_agent: "Barracuda Sentinel (EE)", ip: "203.0.113.9", http_method: "HEAD")

    travel 3.days + 1.minute do
      tick!
    end
    assert_equal [@step1.id, @step2.id], sent_step_ids(subscriber)
    assert_not_includes subscriber.reload.tags, "Clicked email 1"
  end

  test "the finish wait gives the last step's action time, then completes with the completion tag" do
    @sequence.update!(finish_after_minutes: 3.days.in_minutes.to_i, completed_tag: "Did not connect")
    subscriber = enroll!
    tick!
    travel 3.days + 1.minute do
      tick!
    end
    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal "active", enrollment.state, "waiting out the finish window"
    assert_equal 2, enrollment.current_step

    travel 6.days + 2.minutes do
      tick!
    end
    enrollment.reload
    assert_equal "completed", enrollment.state
    assert_includes subscriber.reload.tags, "Did not connect"
  end

  test "hitting the goal during the finish wait exits without the completion tag" do
    @sequence.update!(finish_after_minutes: 3.days.in_minutes.to_i, completed_tag: "Did not connect")
    subscriber = enroll!
    tick!
    travel 3.days + 1.minute do
      tick!
    end
    travel 4.days do
      track!("account:connected")
    end
    travel 6.days + 2.minutes do
      tick!
    end

    assert_equal "goal", @sequence.enrollments.find_by!(subscriber: subscriber).exit_reason
    assert_includes subscriber.reload.tags, "Connected"
    assert_not_includes subscriber.tags, "Did not connect"
  end

  test "without a finish wait the sequence completes right after the last step" do
    @sequence.update!(completed_tag: "Finished")
    subscriber = enroll!
    tick!
    travel 3.days + 1.minute do
      tick!
    end
    assert_equal "completed", @sequence.enrollments.find_by!(subscriber: subscriber).state
    assert_includes subscriber.reload.tags, "Finished"
  end

  test "a tag set by one sequence is usable as another's exit segment" do
    @sequence.update!(exit_segment: tag_segment("Connected"))
    subscriber = enroll!
    tick!
    subscriber.add_tag!("Connected")

    travel 3.days + 1.minute do
      tick!
    end
    assert_equal "exit_segment", @sequence.enrollments.find_by!(subscriber: subscriber).exit_reason
  end

  test "a tag rules-tree segment triggers a sequence on the sweep" do
    tagged = @team.sequences.create!(
      name: "Tagged follow-up", status: "active", trigger_type: "segment",
      trigger_segment: tag_segment("Connected"), sender_address: @sender
    )
    tagged.steps.create!(delay_minutes: 0, subject: "Nice", body_markdown: "Thanks")
    subscriber = enroll!
    subscriber.add_tag!("Connected")
    other = @team.subscribers.create!(email: "other@example.com", subscribed: true)

    SegmentEnrollmentSweepJob.perform_now
    assert_equal [subscriber.id], tagged.enrollments.pluck(:subscriber_id)
    assert_not other.reload.tags.any?
  end

  test "not enrolled in sequence X: an enrollment there, even a finished one, keeps them out" do
    later = @team.sequences.create!(
      name: "Never connected", status: "active", trigger_type: "segment",
      trigger_segment: plan_segment("free"), sender_address: @sender,
      excluded_sequence_ids: [@sequence.id]
    )
    later.steps.create!(delay_minutes: 0, subject: "Hey", body_markdown: "Hi")

    been_through = enroll!
    been_through.update!(custom_attributes: {"plan" => "free"})
    @sequence.enrollments.find_by!(subscriber: been_through).exit!("goal")
    fresh = @team.subscribers.create!(email: "fresh@example.com", subscribed: true,
      custom_attributes: {"plan" => "free"})

    SegmentEnrollmentSweepJob.perform_now
    assert_equal [fresh.id], later.enrollments.pluck(:subscriber_id)
    assert_not later.enrollable?(been_through)
  end

  test "removing a step drops the action it left pending" do
    subscriber = enroll!
    tick!
    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal 0, enrollment.pending_action_step

    @step1.destroy!
    enrollment.reload
    assert_nil enrollment.pending_action_step
    assert_equal 0, enrollment.current_step, "the reminder is now step 0"
  end

  test "a step action is validated" do
    goalless = @team.sequences.create!(name: "No goal", trigger_type: "event", trigger_event_name: "x")
    step = goalless.steps.build(subject: "x", body_markdown: "y", delay_minutes: 0, action_trigger: "click")
    assert_not step.valid?
    assert_includes step.errors[:action_trigger], "needs a tag to add or an exit"

    step.assign_attributes(action_trigger: "goal", action_exit: true)
    assert_not step.valid?
    assert_includes step.errors[:action_trigger], "needs a goal on the sequence"

    step.action_trigger = "bogus"
    assert_not step.valid?

    step.assign_attributes(action_trigger: "", action_tag: "  ", action_exit: true)
    assert step.valid?
    assert_nil step.action_trigger
    assert_not step.action_exit, "no trigger, no action"
  end

  test "excluded sequences must be on the same team" do
    other_team = create(:team)
    foreign = other_team.sequences.create!(name: "Theirs", trigger_type: "event", trigger_event_name: "x")
    @sequence.excluded_sequence_ids = [foreign.id.to_s, ""]
    assert_not @sequence.valid?
    assert_equal [foreign.id], @sequence.excluded_sequence_ids
  end

  private

  def enroll!
    track!("signed_up")
    @team.subscribers.find_by!(external_id: "user-1")
  end

  def track!(event_name, external_id: "user-1")
    perform_enqueued_jobs do
      post "/api/v1/teams/#{@team.id}/events/track",
        params: {external_id: external_id, auto_create: true, email: "#{external_id}@example.com",
                 name: "Sam", event_name: event_name}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{access_token}"}
    end
    assert_response :created
  end

  def tick!
    perform_enqueued_jobs { SequenceDispatchJob.perform_now }
  end

  def sent_step_ids(subscriber)
    subscriber.deliveries.sent.order(:id).pluck(:sequence_step_id)
  end

  def plan_segment(plan)
    @team.segments.create!(name: "Plan #{plan}",
      definition: {"predicate" => "json_extract(custom_attributes, '$.plan') = '#{plan}'"})
  end

  def tag_segment(tag)
    @team.segments.create!(name: "Tagged #{tag}", rules: {
      "type" => "group", "combinator" => "and", "rules" => [
        {"type" => "rule", "field" => "subscribers.tags", "operator" => "contains", "value" => tag}
      ]
    })
  end
end
