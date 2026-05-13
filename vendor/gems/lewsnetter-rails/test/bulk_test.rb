require "test_helper"

# Regression coverage for Lewsnetter::Bulk#bulk_upsert. The historical bug was
# that this method wrapped each subscriber payload in `{subscriber: ...}` --
# matching the single-upsert JSON envelope -- but the server's bulk endpoint
# expects each NDJSON line to be a FLAT subscriber hash. The wrap caused every
# row to fail validation with "Email can't be blank". These tests pin the
# correct flat shape so the regression cannot return silently.
class BulkTest < Minitest::Test
  def setup
    setup_default_config
    FakeNetHttp.reset!
  end

  def teardown
    FakeNetHttp.reset!
    Lewsnetter.client = nil
  end

  # Stand-in for a model that opted in via acts_as_lewsnetter_subscriber.
  # We only need #lewsnetter_payload here.
  FakeRecord = Struct.new(:external_id, :email, :name) do
    def lewsnetter_payload
      {
        external_id: external_id.to_s,
        email: email,
        name: name,
        attributes: {plan: "pro"}
      }
    end
  end

  # Capturing client stub -- replaces Lewsnetter.client for the duration of
  # the test. Records every call to #bulk_upsert_subscribers so we can assert
  # on the exact rows the gem handed to the HTTP layer.
  class CapturingClient
    attr_reader :calls

    def initialize(response: {"processed" => 0, "created" => 0, "updated" => 0, "errors" => []})
      @response = response
      @calls = []
    end

    def bulk_upsert_subscribers(rows)
      @calls << rows
      @response
    end
  end

  def test_bulk_upsert_passes_flat_payloads_no_envelope
    client = CapturingClient.new(response: {"processed" => 2, "created" => 2, "updated" => 0, "errors" => []})
    Lewsnetter.client = client

    records = [
      FakeRecord.new(1, "a@x.com", "Alice"),
      FakeRecord.new(2, "b@x.com", "Bob")
    ]

    totals = Lewsnetter.bulk_upsert(records, batch_size: 500)

    assert_equal 1, client.calls.length, "expected exactly one batched call for 2 records"
    rows = client.calls.first
    assert_equal 2, rows.length

    rows.each do |row|
      assert_kind_of Hash, row
      refute row.key?(:subscriber), "row must be a FLAT hash, not wrapped in :subscriber envelope: #{row.inspect}"
      refute row.key?("subscriber"), "row must be a FLAT hash, not wrapped in 'subscriber' envelope: #{row.inspect}"
      assert row.key?(:external_id), "row must carry :external_id at the top level: #{row.inspect}"
      assert row.key?(:email),       "row must carry :email at the top level: #{row.inspect}"
    end

    # Spot-check the first row matches the record's own lewsnetter_payload --
    # no transformation between record and wire.
    assert_equal records.first.lewsnetter_payload, rows.first

    # Aggregate totals come from the captured response.
    assert_equal 2, totals["processed"]
    assert_equal 2, totals["created"]
  end

  def test_bulk_upsert_ndjson_each_line_is_flat_after_json_serialization
    # End-to-end shape check: drive Bulk through the real Client, capture the
    # NDJSON body the HTTP layer would send, and confirm each line decodes to
    # a flat hash. This is the second line of defence against re-introducing
    # the envelope.
    FakeNetHttp.next_response = FakeResponse.new(
      "200",
      {"processed" => 2, "created" => 1, "updated" => 1, "errors" => []}.to_json
    )

    records = [
      FakeRecord.new(1, "a@x.com", "Alice"),
      FakeRecord.new(2, "b@x.com", "Bob")
    ]

    Lewsnetter.bulk_upsert(records, batch_size: 500)

    req = FakeNetHttp.last_request
    refute_nil req
    assert_equal "/api/v1/teams/99/subscribers/bulk", req.path
    assert_equal "application/x-ndjson", req["Content-Type"]

    lines = req.body.split("\n")
    assert_equal 2, lines.length
    lines.zip(records).each do |line, record|
      parsed = JSON.parse(line)
      refute parsed.key?("subscriber"), "NDJSON line must be flat: #{parsed.inspect}"
      assert_equal record.external_id.to_s, parsed["external_id"]
      assert_equal record.email, parsed["email"]
      assert_equal record.name, parsed["name"]
      assert_equal({"plan" => "pro"}, parsed["attributes"])
    end
  end

  def test_bulk_upsert_aggregates_totals_across_batches
    # With batch_size: 1 the gem should make N calls and sum the response
    # counts. Guards the merge_bulk_result! helper.
    client = CapturingClient.new(response: {"processed" => 1, "created" => 1, "updated" => 0, "errors" => []})
    Lewsnetter.client = client

    records = [
      FakeRecord.new(1, "a@x.com", "Alice"),
      FakeRecord.new(2, "b@x.com", "Bob"),
      FakeRecord.new(3, "c@x.com", "Carol")
    ]

    totals = Lewsnetter.bulk_upsert(records, batch_size: 1)

    assert_equal 3, client.calls.length
    assert_equal 3, totals["processed"]
    assert_equal 3, totals["created"]
    assert_equal 0, totals["updated"]
    assert_equal [], totals["errors"]
  end
end
