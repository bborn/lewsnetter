$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "active_job"
require "active_support"
require "active_support/core_ext"
require "lewsnetter-rails"

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(IO::NULL)

class Minitest::Test
  def setup_default_config
    Lewsnetter.reset_configuration!
    Lewsnetter.client = nil
    Lewsnetter.configure do |c|
      c.api_key = "test-key"
      c.team_id = 99
      c.endpoint = "https://test.lewsnetter.example/api/v1"
      c.async = false
    end
  end
end

# Capture the last Net::HTTP request without hitting the network.
class FakeNetHttp
  class << self
    attr_accessor :last_request, :last_uri, :next_response

    def install!
      @original_request = Net::HTTP.instance_method(:request)
      Net::HTTP.send(:define_method, :request) do |req|
        FakeNetHttp.last_request = req
        FakeNetHttp.last_uri = URI("#{use_ssl? ? "https" : "http"}://#{address}:#{port}#{req.path}")
        FakeNetHttp.next_response || FakeResponse.new("200", {"processed" => 1}.to_json)
      end
    end

    def uninstall!
      Net::HTTP.send(:define_method, :request, @original_request) if @original_request
    end

    def reset!
      @last_request = nil
      @last_uri = nil
      @next_response = nil
    end
  end
end

class FakeResponse
  attr_reader :code, :body

  def initialize(code, body, headers = {})
    @code = code.to_s
    @body = body
    @headers = headers
  end

  def [](key)
    @headers[key]
  end
end

FakeNetHttp.install!
Minitest.after_run { FakeNetHttp.uninstall! }
