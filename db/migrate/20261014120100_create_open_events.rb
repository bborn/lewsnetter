class CreateOpenEvents < ActiveRecord::Migration[8.0]
  # One row per open-pixel fetch, mirroring click_events. Delivery#opened_at
  # stays the raw "first pixel fetch" stamp; this table lets stats separate
  # Apple Mail Privacy Protection prefetches and scanner fetches from
  # people. See OpenEvent + MachineTraffic.
  def change
    create_table :open_events do |t|
      t.references :delivery, null: false, foreign_key: true
      t.datetime :opened_at, null: false
      t.string :user_agent
      t.string :ip_prefix
      t.string :http_method
      t.boolean :automated, null: false, default: false
      t.string :automated_reason
      t.boolean :backfilled, null: false, default: false
      t.timestamps
    end
    add_index :open_events, [:delivery_id, :automated]
  end
end
