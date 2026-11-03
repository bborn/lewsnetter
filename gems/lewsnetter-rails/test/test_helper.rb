# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"
require "active_job"
require "lewsnetter_rails"

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil)

class LewsnetterTest < Minitest::Test
  include ActiveJob::TestHelper

  BASE = "https://lewsnetter.test"
  SLUG = "team-abc"

  def setup
    super
    LewsnetterRails.reset!
    LewsnetterRails.configure do |c|
      c.base_url = BASE
      c.api_token = "test-token"
      c.team_slug = SLUG
      c.enabled = true
      c.retries = 0
    end
    WebMock.disable_net_connect!
  end

  def teardown
    clear_enqueued_jobs
    LewsnetterRails.reset!
    super
  end
end
