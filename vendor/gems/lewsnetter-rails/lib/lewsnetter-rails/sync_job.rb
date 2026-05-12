require "active_job"

module Lewsnetter
  # Pushes a subscriber upsert (or delete) to Lewsnetter. Retries on transient errors.
  class SyncJob < ActiveJob::Base
    queue_as :default

    retry_on Lewsnetter::RateLimitedError, wait: :polynomially_longer, attempts: 5
    retry_on Lewsnetter::ApiError, wait: :polynomially_longer, attempts: 5
    discard_on Lewsnetter::AuthenticationError

    def perform(payload)
      payload = payload.transform_keys(&:to_sym) if payload.respond_to?(:transform_keys)

      if payload[:_delete]
        Lewsnetter.client.delete_subscriber(payload[:external_id])
      else
        Lewsnetter.client.upsert_subscriber(**payload.except(:_delete))
      end
    end
  end
end
