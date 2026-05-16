# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/blank"

module LewsnetterRails
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TransportError < Error; end

  class Configuration
    attr_accessor :base_url, :api_token, :team_slug, :enabled, :job_queue,
      :logger, :timeout, :open_timeout, :retries

    def initialize
      @base_url     = ENV["LEWSNETTER_URL"]
      @api_token    = ENV["LEWSNETTER_API_TOKEN"]
      @team_slug    = ENV["LEWSNETTER_TEAM_SLUG"]
      @enabled      = ENV.fetch("LEWSNETTER_ENABLED", "true") != "false"
      @job_queue    = :default
      @timeout      = 10
      @open_timeout = 5
      @retries      = 3
    end

    def validate!
      missing = []
      missing << "base_url"  if base_url.blank?
      missing << "api_token" if api_token.blank?
      missing << "team_slug" if team_slug.blank?
      raise ConfigurationError, "LewsnetterRails missing: #{missing.join(", ")}" if missing.any?
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset!
      @configuration = nil
    end
  end
end

require "lewsnetter_rails/client"
require "lewsnetter_rails/sync_job"
require "lewsnetter_rails/backfill"
require "lewsnetter_rails/acts_as_subscriber"
