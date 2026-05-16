# frozen_string_literal: true

require "active_job"

module LewsnetterRails
  # ActiveJob that pushes one or many subscribers to Lewsnetter. Used by
  # the acts_as_subscriber after_commit hook (single) and Backfill.run
  # (batched). Keeps retries near the data so a deploy-time blip can't
  # silently drop a sync.
  class SyncJob < ActiveJob::Base
    queue_as { LewsnetterRails.configuration.job_queue }

    retry_on LewsnetterRails::TransportError, wait: :polynomially_longer, attempts: 5
    retry_on Faraday::Error,                  wait: :polynomially_longer, attempts: 5

    # Only registered if the host app actually has ActiveRecord loaded
    # (the gem itself doesn't depend on AR — works fine in non-AR Rack apps).
    discard_on ActiveRecord::RecordNotFound if defined?(ActiveRecord)

    # Sync a single record. `model_class` + `id` so the job arg is small
    # and we re-fetch fresh state on perform (the user may have edited
    # again between enqueue + run).
    def perform(model_class:, id:, mapper:)
      return unless LewsnetterRails.configuration.enabled
      record = model_class.constantize.find(id)
      payload = mapper.constantize.call(record)
      LewsnetterRails::Client.new.upsert(payload)
    end
  end
end
