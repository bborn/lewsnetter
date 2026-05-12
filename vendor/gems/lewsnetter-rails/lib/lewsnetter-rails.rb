require "lewsnetter-rails/version"

module Lewsnetter
  # Error hierarchy.
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class ApiError < Error
    attr_reader :status

    def initialize(message, status: nil)
      @status = status
      super(message)
    end
  end

  class AuthenticationError < ApiError; end

  class RateLimitedError < ApiError
    attr_reader :retry_after

    def initialize(message, status: 429, retry_after: nil)
      @retry_after = retry_after
      super(message, status: status)
    end
  end
end

require "lewsnetter-rails/configuration"
require "lewsnetter-rails/client"
require "lewsnetter-rails/subscriber"
require "lewsnetter-rails/sync_job"
require "lewsnetter-rails/track_job"
require "lewsnetter-rails/tracker"
require "lewsnetter-rails/bulk"

module Lewsnetter
  extend Tracker
  extend Bulk

  class << self
    # Yields the global configuration for setup.
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # The shared client. Reset via `Lewsnetter.client = nil` if needed.
    def client
      @client ||= Client.new(configuration)
    end

    attr_writer :client
  end
end

require "lewsnetter-rails/railtie" if defined?(Rails::Railtie)
