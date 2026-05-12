require "active_job"

module Lewsnetter
  # Pushes a single behavioral event to Lewsnetter.
  class TrackJob < ActiveJob::Base
    queue_as :default

    retry_on Lewsnetter::RateLimitedError, wait: :polynomially_longer, attempts: 5
    retry_on Lewsnetter::ApiError, wait: :polynomially_longer, attempts: 5
    discard_on Lewsnetter::AuthenticationError

    def perform(payload)
      payload = payload.transform_keys(&:to_sym) if payload.respond_to?(:transform_keys)
      Lewsnetter.client.track_event(**payload)
    end
  end
end
