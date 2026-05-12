class AddIndexForWebhooksOutgoingAttempts < ActiveRecord::Migration[8.0]
  # `algorithm: :concurrently` is a Postgres-only feature; SQLite has no
  # equivalent. We drop both `disable_ddl_transaction!` and the algorithm
  # option so this runs as a regular DDL statement on SQLite.
  def change
    add_index :webhooks_outgoing_delivery_attempts, :delivery_id
  end
end
