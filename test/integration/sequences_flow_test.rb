require "controllers/api/v1/test"

# End-to-end Sequences: a tracked event enrolls, the dispatcher sends each
# step on schedule (time travel), and unsubscribe / suppression / exit
# segment stop the flow. Real models throughout; only SES is stubbed (the
# app's built-in :stub client).
class SequencesFlowTest < Api::V1::Test
  include ActiveJob::TestHelper

  setup do
    @team.update!(sequences_enabled: true)
    @sender = @team.sender_addresses.create!(
      email: "hello@example.com", name: "Hello", verified: true, ses_status: "verified"
    )
    @sequence = @team.sequences.create!(
      name: "Welcome", status: "active", trigger_type: "event",
      trigger_event_name: "signed_up", sender_address: @sender
    )
    @step1 = @sequence.steps.create!(delay_minutes: 0, subject: "Welcome", body_markdown: "Hi {{subscriber.name}}")
    @step2 = @sequence.steps.create!(delay_minutes: 1.day.in_minutes.to_i, subject: "Day 1", body_markdown: "Tips")
    @step3 = @sequence.steps.create!(delay_minutes: 2.days.in_minutes.to_i, subject: "Day 3", body_markdown: "More")

    @original_ses = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
  end

  teardown do
    Rails.application.config.ses_client = @original_ses
  end

  test "a tracked event enrolls and every step sends on schedule" do
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal "active", enrollment.state

    tick!
    assert_equal [@step1.id], sent_step_ids(subscriber)
    delivery = subscriber.deliveries.last
    assert_equal @step1.campaign, delivery.campaign
    assert_not_nil delivery.ses_message_id

    travel 23.hours do
      tick!
      assert_equal [@step1.id], sent_step_ids(subscriber), "step 2 must wait a full day"
    end

    travel 1.day + 1.minute do
      tick!
      assert_equal [@step1.id, @step2.id], sent_step_ids(subscriber)

      tick! # same instant again: no double send
      assert_equal 2, subscriber.deliveries.count
    end

    travel 3.days + 2.minutes do
      tick!
    end
    assert_equal [@step1.id, @step2.id, @step3.id], sent_step_ids(subscriber)
    enrollment.reload
    assert_equal "completed", enrollment.state
    assert_not_nil enrollment.completed_at
    assert_equal 3, subscriber.reload.times_contacted
    assert_equal [1, 1, 1], @sequence.reload.step_stats.map { it[:sent] }
  end

  test "unsubscribing mid-sequence stops it" do
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    tick!

    get URI(UnsubscribeUrlHelper.url_for(subscriber: subscriber)).path
    assert_response :success
    assert_not subscriber.reload[:subscribed]

    travel 2.days do
      tick!
    end
    assert_equal [@step1.id], sent_step_ids(subscriber)
    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal "exited", enrollment.state
    assert_equal "unsubscribed", enrollment.exit_reason
  end

  test "a suppressed address gets no more steps" do
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    tick!
    Suppression.suppress(team: @team, email: subscriber.email, reason: "complaint")

    travel 2.days do
      tick!
    end
    assert_equal [@step1.id], sent_step_ids(subscriber)
    assert_equal "suppressed", @sequence.enrollments.find_by!(subscriber: subscriber).state
  end

  test "matching the exit segment ends the sequence before the next step" do
    @sequence.update!(exit_segment: paid_segment)
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    tick!

    subscriber.update!(custom_attributes: {"plan" => "paid"})
    travel 2.days do
      tick!
    end
    assert_equal [@step1.id], sent_step_ids(subscriber)
    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    assert_equal "exited", enrollment.state
    assert_equal "exit_segment", enrollment.exit_reason
  end

  test "the hourly sweep exits enrollments that match the exit segment" do
    @sequence.update!(exit_segment: paid_segment)
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    subscriber.update!(custom_attributes: {"plan" => "paid"})

    SegmentEnrollmentSweepJob.perform_now
    assert_equal "exit_segment", @sequence.enrollments.find_by!(subscriber: subscriber).exit_reason
  end

  test "a step's skip segment skips that step only" do
    @step2.update!(skip_segment: paid_segment)
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    subscriber.update!(custom_attributes: {"plan" => "paid"})
    tick!

    travel 1.day + 1.minute do
      tick! # step 2: skipped, step 3 scheduled 2 days from now
    end
    assert_equal 1, @step2.reload.skipped_count
    travel 3.days + 2.minutes do
      tick!
    end
    assert_equal [@step1.id, @step3.id], sent_step_ids(subscriber)
  end

  test "re-entry: a repeat event re-enrolls only after reentry_days" do
    @sequence.update!(reentry_days: 30)
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    @sequence.enrollments.find_by!(subscriber: subscriber).update!(state: "completed")

    travel 10.days do
      track!("signed_up")
      assert_equal 1, @sequence.enrollments.where(subscriber: subscriber).count
    end
    travel 31.days do
      track!("signed_up")
      assert_equal 2, @sequence.enrollments.where(subscriber: subscriber).count
    end
  end

  test "events older than the enrollment window, other names, and flag-off teams don't enroll" do
    track!("signed_up", occurred_at: 3.days.ago.iso8601)
    track!("logged_in", external_id: "user-2")
    @team.update!(sequences_enabled: false)
    track!("signed_up", external_id: "user-3")

    assert_equal 0, @sequence.enrollments.count
  end

  test "segment-triggered sequences enroll on the hourly sweep" do
    segment = paid_segment
    seq = @team.sequences.create!(name: "Paid", status: "active", trigger_type: "segment",
      trigger_segment: segment, sender_address: @sender)
    seq.steps.create!(delay_minutes: 0, subject: "Thanks", body_markdown: "Thanks for upgrading")
    paid = @team.subscribers.create!(email: "p@example.com", external_id: "p", custom_attributes: {"plan" => "paid"})
    @team.subscribers.create!(email: "f@example.com", external_id: "f", custom_attributes: {"plan" => "free"})

    SegmentEnrollmentSweepJob.perform_now
    SegmentEnrollmentSweepJob.perform_now
    assert_equal [paid.id], seq.enrollments.pluck(:subscriber_id)
  end

  test "a failing send retries, then exits after MAX_ATTEMPTS" do
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    # Fail at the SES boundary: a client whose send_email raises.
    Rails.application.config.ses_client = nil
    failing_client = Object.new
    failing_client.define_singleton_method(:send_email) { |**| raise "SES unavailable" }
    original_client_for = Ses::ClientFor.method(:call)
    Ses::ClientFor.define_singleton_method(:call) { |_team| failing_client }

    enrollment = @sequence.enrollments.find_by!(subscriber: subscriber)
    tick!
    assert_equal 1, enrollment.reload.attempts
    assert_equal "active", enrollment.state
    travel 61.minutes do
      tick!
    end
    travel 122.minutes do
      tick!
    end
    enrollment.reload
    assert_equal "exited", enrollment.state
    assert_equal "send_failed", enrollment.exit_reason
    assert_equal 3, subscriber.deliveries.where(status: "failed").count
  ensure
    Ses::ClientFor.define_singleton_method(:call, original_client_for) if original_client_for
  end

  test "pausing a sequence holds sends; reactivating resumes them" do
    track!("signed_up")
    subscriber = @team.subscribers.find_by!(external_id: "user-1")
    @sequence.update!(status: "paused")
    tick!
    assert_equal [], sent_step_ids(subscriber)

    @sequence.update!(status: "active")
    tick!
    assert_equal [@step1.id], sent_step_ids(subscriber)
  end

  private

  def track!(event_name, external_id: "user-1", occurred_at: nil)
    perform_enqueued_jobs do
      post "/api/v1/teams/#{@team.id}/events/track",
        params: {external_id: external_id, auto_create: true, email: "#{external_id}@example.com",
                 name: "Sam", event_name: event_name, occurred_at: occurred_at}.compact.to_json,
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

  def paid_segment
    @team.segments.create!(name: "Paid",
      definition: {"predicate" => "json_extract(custom_attributes, '$.plan') = 'paid'"})
  end
end
