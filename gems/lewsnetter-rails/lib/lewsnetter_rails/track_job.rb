# frozen_string_literal: true

require "active_job"
require "time"

module LewsnetterRails
  # ActiveJob behind LewsnetterRails.track. Arguments are plain strings and
  # hashes (occurred_at as ISO-8601) so they serialize on every backend.
  # occurred_at is captured at enqueue time: a job that retries an hour
  # later still records when the thing actually happened.
  class TrackJob < ActiveJob::Base
    queue_as { LewsnetterRails.configuration.job_queue }

    retry_on LewsnetterRails::TransportError, wait: :polynomially_longer, attempts: 5
    retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5

    def perform(external_id:, name:, occurred_at: nil, properties: {})
      return unless LewsnetterRails.configuration.enabled
      LewsnetterRails::Client.new.track_event(
        external_id: external_id,
        name: name,
        occurred_at: occurred_at && Time.iso8601(occurred_at),
        properties: properties
      )
    end
  end
end
