module Lewsnetter
  module Bulk
    # Lewsnetter.bulk_upsert(User.where(active: true)) — streams in batches.
    # Returns aggregate {processed:, created:, updated:, errors: []}.
    def bulk_upsert(scope, batch_size: 500)
      totals = {"processed" => 0, "created" => 0, "updated" => 0, "errors" => []}

      each_batch(scope, batch_size) do |batch|
        rows = batch.map { |record| {subscriber: record.lewsnetter_payload} }
        result = Lewsnetter.client.bulk_upsert_subscribers(rows)
        merge_bulk_result!(totals, result)
      end

      totals
    end

    private

    def each_batch(scope, batch_size)
      if scope.respond_to?(:find_in_batches)
        scope.find_in_batches(batch_size: batch_size) { |batch| yield batch }
      else
        scope.to_a.each_slice(batch_size) { |batch| yield batch }
      end
    end

    def merge_bulk_result!(totals, result)
      return unless result.is_a?(Hash)
      %w[processed created updated].each do |k|
        totals[k] += result[k].to_i if result.key?(k)
      end
      totals["errors"].concat(Array(result["errors"]))
    end
  end
end
