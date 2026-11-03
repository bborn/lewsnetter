# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/blank"

module LewsnetterRails
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TransportError < Error; end

  class Configuration
    attr_accessor :base_url, :api_token, :team_slug, :enabled, :job_queue,
      :logger, :timeout, :open_timeout, :retries, :external_id_method

    def initialize
      @base_url = ENV["LEWSNETTER_URL"]
      @api_token = ENV["LEWSNETTER_API_TOKEN"]
      @team_slug = ENV["LEWSNETTER_TEAM_SLUG"]
      @enabled = ENV.fetch("LEWSNETTER_ENABLED", "true") != "false"
      @job_queue = :default
      @timeout = 10
      @open_timeout = 5
      @retries = 3
      @external_id_method = :id
    end

    def validate!
      missing = []
      missing << "base_url" if base_url.blank?
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

    # Track an event for a subscriber, e.g. from a controller or model:
    #
    #   LewsnetterRails.track(current_user, "trial_started", plan: "pro")
    #   LewsnetterRails.track("user-42", "invoice_paid", {amount: 99}, occurred_at: paid_at)
    #
    # `subscriber` is an external_id or any object responding to the
    # configured `external_id_method` (default :id). Enqueues TrackJob so
    # the request never waits on Lewsnetter; pass `async: false` to send
    # inline. A no-op when the gem is disabled.
    def track(subscriber, name, properties = {}, occurred_at: Time.now, async: true)
      return unless configuration.enabled

      external_id = external_id_for(subscriber)
      raise ArgumentError, "LewsnetterRails.track needs a subscriber" if external_id.blank?
      raise ArgumentError, "LewsnetterRails.track needs an event name" if name.blank?

      args = {
        external_id: external_id,
        name: name.to_s,
        occurred_at: occurred_at&.iso8601,
        properties: properties.to_h.transform_keys(&:to_s)
      }
      if async
        TrackJob.perform_later(**args)
      else
        Client.new.track_event(**args.merge(occurred_at: occurred_at))
      end
    end

    def external_id_for(subscriber)
      return subscriber.to_s if subscriber.is_a?(String) || subscriber.is_a?(Integer)
      subscriber.public_send(configuration.external_id_method).to_s
    end
  end
end

require "lewsnetter_rails/client"
require "lewsnetter_rails/sync_job"
require "lewsnetter_rails/track_job"
require "lewsnetter_rails/backfill"
require "lewsnetter_rails/acts_as_subscriber"
