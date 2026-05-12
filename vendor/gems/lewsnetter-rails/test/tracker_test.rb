require "test_helper"

class TrackerTest < Minitest::Test
  class FakeRecord
    attr_reader :id
    def initialize(id)
      @id = id
    end
  end

  def setup
    setup_default_config
    Lewsnetter.configuration.async = true
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def test_track_enqueues_track_job_for_record
    Lewsnetter.track(FakeRecord.new(42), "report_viewed", report_id: 7)
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal 1, enqueued.length
    assert_equal "Lewsnetter::TrackJob", enqueued.first[:job].name
    payload = enqueued.first[:args].first
    assert_equal "42", payload[:external_id] || payload["external_id"]
    assert_equal "report_viewed", payload[:event] || payload["event"]
  end

  def test_track_accepts_string_external_id
    Lewsnetter.track("ext_77", "signed_up")
    payload = ActiveJob::Base.queue_adapter.enqueued_jobs.first[:args].first
    assert_equal "ext_77", payload[:external_id] || payload["external_id"]
  end

  def test_track_runs_inline_when_async_false
    Lewsnetter.configuration.async = false
    FakeNetHttp.next_response = FakeResponse.new("200", "{}")
    Lewsnetter.track("ext_1", "logged_in", source: "web")
    req = FakeNetHttp.last_request
    assert_equal "/api/v1/teams/99/events/track", req.path
    body = JSON.parse(req.body)
    assert_equal "ext_1", body["external_id"]
    assert_equal "logged_in", body["event"]
    assert_equal "web", body["properties"]["source"]
  end
end
