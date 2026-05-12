require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    Lewsnetter.reset_configuration!
  end

  def test_defaults
    cfg = Lewsnetter.configuration
    assert_equal "https://app.lewsnetter.com/api/v1", cfg.endpoint
    assert_equal true, cfg.async
    assert_equal 5, cfg.http_open_timeout
    assert_equal 15, cfg.http_read_timeout
  end

  def test_configure_block_sets_values
    Lewsnetter.configure do |c|
      c.api_key = "abc"
      c.team_id = 7
      c.endpoint = "http://localhost:3000/api/v1"
      c.async = false
    end
    cfg = Lewsnetter.configuration
    assert_equal "abc", cfg.api_key
    assert_equal 7, cfg.team_id
    assert_equal "http://localhost:3000/api/v1", cfg.endpoint
    refute cfg.async
  end

  def test_url_helpers
    Lewsnetter.configure do |c|
      c.api_key = "k"
      c.team_id = 42
      c.endpoint = "https://example.test/api/v1"
    end
    cfg = Lewsnetter.configuration
    assert_equal "https://example.test/api/v1/teams/42/subscribers", cfg.subscribers_url
    assert_equal "https://example.test/api/v1/teams/42/subscribers/bulk", cfg.subscribers_bulk_url
    assert_equal "https://example.test/api/v1/teams/42/events/track", cfg.events_track_url
    assert_equal "https://example.test/api/v1/teams/42/events/bulk", cfg.events_bulk_url
    assert_equal "https://example.test/api/v1/teams/42/subscribers/by_external_id/abc", cfg.subscriber_by_external_id_url("abc")
  end

  def test_validate_raises_without_required_fields
    assert_raises(Lewsnetter::ConfigurationError) { Lewsnetter.configuration.validate! }
  end
end
