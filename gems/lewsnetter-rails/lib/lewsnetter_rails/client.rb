# frozen_string_literal: true

require "faraday"
require "faraday/retry"

module LewsnetterRails
  # Thin HTTP client for Lewsnetter's subscriber, event and suppression
  # endpoints. Retries on
  # 429 / 5xx with exponential backoff so transient blips don't lose syncs.
  # The job layer also retries — these retries are belt + suspenders.
  class Client
    def initialize(config: LewsnetterRails.configuration)
      config.validate!
      @config = config
    end

    # Upsert a single subscriber by external_id. Body is whatever shape
    # the caller's mapper produces, must include `external_id` and `email`.
    def upsert(payload)
      bulk([payload])
    end

    # Upsert many subscribers via the NDJSON bulk endpoint. Returns the
    # summary {processed:, created:, updated:, errors:}. Idempotent on
    # external_id — safe to retry.
    def bulk(payloads)
      return {processed: 0, created: 0, updated: 0, errors: []} if payloads.empty?
      ndjson = payloads.map(&:to_json).join("\n")
      response = connection.post(bulk_path, ndjson, "Content-Type" => "application/x-ndjson")
      handle_response(response)
    end

    # Record an event against the subscriber with this external_id. Events
    # drive event-triggered Sequences. Returns the created event as JSON.
    # Raises TransportError on 404 (unknown external_id) — sync the user
    # first, or pass `email:` with `auto_create: true`.
    def track_event(external_id:, name:, occurred_at: nil, properties: {}, email: nil, auto_create: false)
      body = {
        external_id: external_id.to_s,
        event_name: name.to_s,
        occurred_at: occurred_at&.iso8601,
        properties: properties || {}
      }
      if auto_create
        body[:auto_create] = true
        body[:email] = email
      end
      response = connection.post(track_path, body.compact.to_json, "Content-Type" => "application/json")
      handle_response(response)
    end

    # Add an address to the team's suppression list (nothing sends to it
    # again). Idempotent: an address already on the list returns 200 with
    # created: false. `reason` is one of Lewsnetter's Suppression::REASONS
    # (defaults to "manual" server-side).
    def suppress(email:, reason: nil, note: nil, source: nil)
      body = {email: email, reason: reason, note: note, source: source}.compact
      response = connection.post(suppressions_path, body.to_json, "Content-Type" => "application/json")
      handle_response(response)
    end

    # Hard delete by external_id (GDPR-style).
    def delete(external_id:)
      response = connection.delete(delete_path(external_id))
      handle_response(response)
    end

    private

    attr_reader :config

    def connection
      @connection ||= Faraday.new(url: config.base_url) do |f|
        f.request :authorization, "Bearer", config.api_token
        f.request :retry, max: config.retries, interval: 0.5, backoff_factor: 2,
          retry_statuses: [429, 500, 502, 503, 504],
          methods: %i[get post put delete]
        f.options.timeout = config.timeout
        f.options.open_timeout = config.open_timeout
        f.adapter Faraday.default_adapter
      end
    end

    def bulk_path
      "/api/v1/teams/#{config.team_slug}/subscribers/bulk"
    end

    def track_path
      "/api/v1/teams/#{config.team_slug}/events/track"
    end

    def suppressions_path
      "/api/v1/teams/#{config.team_slug}/suppressions"
    end

    def delete_path(external_id)
      "/api/v1/teams/#{config.team_slug}/subscribers/by_external_id/#{external_id}"
    end

    def handle_response(response)
      if response.success?
        response.body.is_a?(String) ? safely_parse(response.body) : response.body
      else
        raise TransportError, "Lewsnetter #{response.status}: #{response.body.to_s[0, 500]}"
      end
    end

    def safely_parse(body)
      require "json"
      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
