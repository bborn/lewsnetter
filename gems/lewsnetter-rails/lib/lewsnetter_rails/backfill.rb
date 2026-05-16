# frozen_string_literal: true

module LewsnetterRails
  # Nightly catch-up: push a scope of records to Lewsnetter in batches.
  # Picks up anything the webhook-driven sync missed (deploys, failures,
  # records updated before the gem was installed). Idempotent on
  # external_id, safe to re-run.
  #
  # Usage from a cron / scheduled job in the source app:
  #
  #   LewsnetterRails::Backfill.run(
  #     User.where("updated_at > ?", 24.hours.ago),
  #     mapper: "Lewsnetter::UserMapper"
  #   )
  class Backfill
    BATCH_SIZE = 200

    def self.run(scope, mapper:, batch_size: BATCH_SIZE, logger: LewsnetterRails.configuration.logger)
      return unless LewsnetterRails.configuration.enabled
      client = Client.new
      mapper = mapper.constantize if mapper.is_a?(String)
      total = 0
      scope.find_in_batches(batch_size: batch_size) do |batch|
        payloads = batch.map { |r| mapper.call(r) }.compact
        next if payloads.empty?
        summary = client.bulk(payloads)
        total += payloads.size
        logger&.info("[LewsnetterRails] backfilled batch (size=#{payloads.size}) #{summary.inspect}")
      end
      logger&.info("[LewsnetterRails] backfill complete (total=#{total})")
      total
    end
  end
end
