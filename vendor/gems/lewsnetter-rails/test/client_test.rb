require "test_helper"

class ClientTest < Minitest::Test
  def setup
    setup_default_config
    FakeNetHttp.reset!
  end

  def teardown
    FakeNetHttp.reset!
  end

  def test_upsert_subscriber_request_shape
    FakeNetHttp.next_response = FakeResponse.new("201", {"id" => 1, "external_id" => "u_1"}.to_json)

    result = Lewsnetter.client.upsert_subscriber(
      external_id: "u_1",
      email: "a@example.com",
      name: "Alice",
      attributes: {plan: "growth"}
    )

    req = FakeNetHttp.last_request
    refute_nil req, "expected an HTTP request to have been issued"
    assert_equal "/api/v1/teams/99/subscribers", req.path
    assert_equal "application/json", req["Content-Type"]
    assert_equal "Bearer test-key", req["Authorization"]
    assert_match(/^[0-9a-f]{64}$/, req["Idempotency-Key"])

    body = JSON.parse(req.body)
    assert_equal "u_1", body["subscriber"]["external_id"]
    assert_equal "a@example.com", body["subscriber"]["email"]
    assert_equal "Alice", body["subscriber"]["name"]
    assert_equal true, body["subscriber"]["subscribed"]
    assert_equal({"plan" => "growth"}, body["subscriber"]["attributes"])

    assert_equal 1, result["id"]
  end

  def test_track_event_request_shape
    FakeNetHttp.next_response = FakeResponse.new("200", "{}")

    Lewsnetter.client.track_event(
      external_id: "u_1",
      event: "report_viewed",
      properties: {report_id: 42}
    )

    req = FakeNetHttp.last_request
    assert_equal "/api/v1/teams/99/events/track", req.path
    body = JSON.parse(req.body)
    assert_equal "u_1", body["external_id"]
    assert_equal "report_viewed", body["event"]
    assert_equal({"report_id" => 42}, body["properties"])
    refute_nil body["occurred_at"]
  end

  def test_bulk_upsert_sends_ndjson
    FakeNetHttp.next_response = FakeResponse.new("200", {"processed" => 2}.to_json)

    # The bulk endpoint expects FLAT subscriber hashes per NDJSON line --
    # no `{subscriber: ...}` envelope. That wrapper is only used by the
    # single-upsert JSON endpoint (`POST /subscribers` with `params.require(:subscriber)`).
    rows = [
      {external_id: "1", email: "a@x.com", name: "Alice"},
      {external_id: "2", email: "b@x.com", name: "Bob"}
    ]
    result = Lewsnetter.client.bulk_upsert_subscribers(rows)

    req = FakeNetHttp.last_request
    assert_equal "/api/v1/teams/99/subscribers/bulk", req.path
    assert_equal "application/x-ndjson", req["Content-Type"]
    lines = req.body.split("\n")
    assert_equal 2, lines.length
    parsed = JSON.parse(lines[0])
    assert_equal "1", parsed["external_id"]
    assert_equal "a@x.com", parsed["email"]
    refute parsed.key?("subscriber"), "bulk NDJSON lines must not wrap in subscriber envelope"
    assert_equal 2, result["processed"]
  end

  def test_delete_subscriber_request_shape
    FakeNetHttp.next_response = FakeResponse.new("204", "")
    Lewsnetter.client.delete_subscriber("u_1")
    req = FakeNetHttp.last_request
    assert_equal "/api/v1/teams/99/subscribers/by_external_id/u_1", req.path
    assert_instance_of Net::HTTP::Delete, req
    assert_equal "Bearer test-key", req["Authorization"]
  end

  def test_401_raises_authentication_error
    FakeNetHttp.next_response = FakeResponse.new("401", "{}")
    assert_raises(Lewsnetter::AuthenticationError) do
      Lewsnetter.client.upsert_subscriber(external_id: "u_1")
    end
  end

  def test_429_raises_rate_limited_with_retry_after
    FakeNetHttp.next_response = FakeResponse.new("429", "{}", {"Retry-After" => "30"})
    err = assert_raises(Lewsnetter::RateLimitedError) do
      Lewsnetter.client.upsert_subscriber(external_id: "u_1")
    end
    assert_equal 429, err.status
    assert_equal "30", err.retry_after
  end

  def test_500_raises_api_error
    FakeNetHttp.next_response = FakeResponse.new("500", "boom")
    err = assert_raises(Lewsnetter::ApiError) do
      Lewsnetter.client.upsert_subscriber(external_id: "u_1")
    end
    assert_equal 500, err.status
  end

  def test_validates_configuration_before_request
    Lewsnetter.reset_configuration!
    Lewsnetter.client = nil
    assert_raises(Lewsnetter::ConfigurationError) do
      Lewsnetter.client.upsert_subscriber(external_id: "u_1")
    end
  end

  def test_idempotency_key_changes_with_payload
    FakeNetHttp.next_response = FakeResponse.new("200", "{}")
    Lewsnetter.client.upsert_subscriber(external_id: "u_1", email: "a@x.com")
    key_a = FakeNetHttp.last_request["Idempotency-Key"]

    FakeNetHttp.next_response = FakeResponse.new("200", "{}")
    Lewsnetter.client.upsert_subscriber(external_id: "u_1", email: "b@x.com")
    key_b = FakeNetHttp.last_request["Idempotency-Key"]

    refute_equal key_a, key_b
  end
end
