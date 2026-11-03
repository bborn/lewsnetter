# frozen_string_literal: true

require "test_helper"

class TrackTest < LewsnetterTest
  User = Struct.new(:id, :uuid)

  def test_track_enqueues_a_job_with_serializable_args
    at = Time.utc(2026, 11, 3, 9, 30, 0)
    LewsnetterRails.track(User.new(42), "trial_started", {plan: "pro"}, occurred_at: at)

    assert_enqueued_with(job: LewsnetterRails::TrackJob, args: [{
      external_id: "42",
      name: "trial_started",
      occurred_at: "2026-11-03T09:30:00Z",
      properties: {"plan" => "pro"}
    }])
  end

  def test_the_job_posts_the_event_with_the_original_occurred_at
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .with(body: hash_including(
        "external_id" => "42", "event_name" => "trial_started",
        "occurred_at" => "2026-11-03T09:30:00Z", "properties" => {"plan" => "pro"}
      ))
      .to_return(status: 201, body: "{}")

    perform_enqueued_jobs do
      LewsnetterRails.track(User.new(42), "trial_started", {plan: "pro"},
        occurred_at: Time.utc(2026, 11, 3, 9, 30, 0))
    end
    assert_requested stub
  end

  def test_the_job_retries_when_the_subscriber_is_not_synced_yet
    stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .to_return(status: 404, body: "{}")

    # retry_on catches the 404 and re-enqueues instead of raising.
    LewsnetterRails::TrackJob.perform_now(external_id: "42", name: "signed_up")
    assert_enqueued_jobs 1, only: LewsnetterRails::TrackJob
  end

  def test_track_sends_inline_with_async_false
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .with(body: hash_including("external_id" => "user-7", "event_name" => "invoice_paid"))
      .to_return(status: 201, body: "{}")

    LewsnetterRails.track("user-7", "invoice_paid", {amount: 99}, async: false)
    assert_requested stub
    assert_no_enqueued_jobs
  end

  def test_external_id_method_is_configurable
    LewsnetterRails.configuration.external_id_method = :uuid
    LewsnetterRails.track(User.new(1, "u-abc"), "signed_up")
    assert_equal "u-abc", enqueued_jobs.last[:args].first["external_id"]
  end

  def test_track_is_a_no_op_when_disabled
    LewsnetterRails.configuration.enabled = false
    LewsnetterRails.track(User.new(1), "signed_up", async: false)
    assert_no_enqueued_jobs
    assert_not_requested :any, /lewsnetter/
  end

  def test_track_rejects_blank_name
    assert_raises(ArgumentError) { LewsnetterRails.track("1", "") }
  end
end
