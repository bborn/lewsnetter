# frozen_string_literal: true

require "test_helper"

class ClientTest < LewsnetterTest
  def test_track_event_posts_to_the_team_track_endpoint
    at = Time.utc(2026, 11, 3, 12, 0, 0)
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .with(
        headers: {"Authorization" => "Bearer test-token", "Content-Type" => "application/json"},
        body: {
          external_id: "42",
          event_name: "trial_started",
          occurred_at: "2026-11-03T12:00:00Z",
          properties: {plan: "pro"}
        }.to_json
      )
      .to_return(status: 201, body: {id: 7, name: "trial_started"}.to_json)

    result = LewsnetterRails::Client.new.track_event(
      external_id: 42, name: :trial_started, occurred_at: at, properties: {plan: "pro"}
    )

    assert_requested stub
    assert_equal({"id" => 7, "name" => "trial_started"}, result)
  end

  def test_track_event_omits_occurred_at_when_not_given
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .with { |req| !JSON.parse(req.body).key?("occurred_at") }
      .to_return(status: 201, body: "{}")

    LewsnetterRails::Client.new.track_event(external_id: "1", name: "signed_up")
    assert_requested stub
  end

  def test_track_event_can_auto_create_the_subscriber
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .with(body: hash_including("auto_create" => true, "email" => "new@example.com"))
      .to_return(status: 201, body: "{}")

    LewsnetterRails::Client.new.track_event(
      external_id: "9", name: "signed_up", email: "new@example.com", auto_create: true
    )
    assert_requested stub
  end

  def test_track_event_raises_transport_error_on_unknown_subscriber
    stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .to_return(status: 404, body: {error: "Subscriber not found for external_id=1"}.to_json)

    error = assert_raises(LewsnetterRails::TransportError) do
      LewsnetterRails::Client.new.track_event(external_id: "1", name: "signed_up")
    end
    assert_match "404", error.message
  end

  def test_track_event_retries_server_errors
    LewsnetterRails.configuration.retries = 2
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/events/track")
      .to_return({status: 503}, {status: 201, body: "{}"})

    LewsnetterRails::Client.new.track_event(external_id: "1", name: "signed_up")
    assert_requested stub, times: 2
  end

  def test_suppress_posts_to_the_suppressions_endpoint
    stub = stub_request(:post, "#{BASE}/api/v1/teams/#{SLUG}/suppressions")
      .with(body: {email: "gone@example.com", reason: "manual", source: "influencekit"}.to_json)
      .to_return(status: 201, body: {email: "gone@example.com", created: true}.to_json)

    result = LewsnetterRails::Client.new.suppress(
      email: "gone@example.com", reason: "manual", source: "influencekit"
    )
    assert_requested stub
    assert_equal true, result["created"]
  end

  def test_missing_configuration_raises
    LewsnetterRails.configuration.api_token = nil
    assert_raises(LewsnetterRails::ConfigurationError) { LewsnetterRails::Client.new }
  end
end
