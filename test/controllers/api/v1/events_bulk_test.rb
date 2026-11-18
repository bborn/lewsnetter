require "controllers/api/v1/test"

class Api::V1::EventsBulkTest < Api::V1::Test
  include ActiveJob::TestHelper

  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  test "every bulk event needs a nonblank external ID while valid rows still succeed" do
    @team.update!(sequences_enabled: true)
    unlinked = @team.subscribers.create!(email: "unlinked@example.test")
    known = @team.subscribers.create!(email: "known@example.test", external_id: "known")
    rows = [
      {event: "missing"},
      {external_id: nil, event: "null"},
      {external_id: " ", event: "blank"},
      {external_id: "known", event: "valid"},
      {external_id: "unknown", event: "unknown"}
    ]

    post "/api/v1/teams/#{@team.id}/events/bulk",
      params: rows.map(&:to_json).join("\n") + "\n",
      headers: {"CONTENT_TYPE" => "application/x-ndjson", "Authorization" => "Bearer #{access_token}"}

    assert_response :success
    assert_empty unlinked.events.pluck(:name)
    assert_equal ["valid"], known.events.pluck(:name)
    assert_enqueued_jobs 1, only: EnrollOnEventJob
    assert_equal({
      "processed" => 5,
      "created" => 1,
      "errors" => [
        {"line" => 1, "error" => "external_id is required"},
        {"line" => 2, "error" => "external_id is required"},
        {"line" => 3, "error" => "external_id is required"},
        {"line" => 5, "error" => "Subscriber not found for external_id=unknown"}
      ]
    }, response.parsed_body)
  end
end
