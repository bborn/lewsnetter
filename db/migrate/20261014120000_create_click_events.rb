class CreateClickEvents < ActiveRecord::Migration[8.0]
  # One row per click-tracking hit. Delivery#clicked_at / click_count /
  # last_clicked_url keep working as raw counters; this table is what lets
  # us tell a corporate link scanner (Safe Links, Proofpoint, Mimecast…)
  # apart from a person. See ClickEvent + MachineTraffic for the rules.
  #
  # `ip_prefix` is an anonymized network prefix (IPv4 /24, IPv6 /48), never
  # the full address. `backfilled` marks rows synthesized from the legacy
  # Delivery columns by `rails engagement:backfill_events` — those were
  # classified on timing alone.
  def change
    create_table :click_events do |t|
      t.references :delivery, null: false, foreign_key: true
      t.text :url
      t.datetime :clicked_at, null: false
      t.string :user_agent
      t.string :ip_prefix
      t.string :http_method
      t.boolean :honeypot, null: false, default: false
      t.boolean :automated, null: false, default: false
      t.string :automated_reason
      t.boolean :backfilled, null: false, default: false
      t.timestamps
    end
    add_index :click_events, [:delivery_id, :clicked_at]
    add_index :click_events, [:delivery_id, :automated]
  end
end
