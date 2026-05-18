class CreateDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :deliveries do |t|
      t.references :campaign, null: false, foreign_key: true, type: :integer
      t.references :subscriber, null: false, foreign_key: true, type: :integer

      # SES MessageId from the SendEmail response. Nullable so we can store
      # rows for stub-mode sends (synthetic ids are stored as-is) and for
      # outright failures where SES never returned an id.
      t.string :ses_message_id

      # sent | delivered | bounced | complained | failed
      t.string :status, null: false, default: "sent"

      # The four event-correlated timestamps SES gives us via SNS event
      # publishing. opened_at / clicked_at / unsubscribed_at are populated by
      # Phase 2 (client-side pixel + link rewriting) — left nullable here so
      # the model + scopes are stable across both phases.
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :bounced_at
      t.datetime :complained_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.datetime :unsubscribed_at

      t.integer :click_count, null: false, default: 0

      # Permanent | Transient | Undetermined (SES bounce sub-classification).
      t.string :bounce_subtype
      t.text :error_message

      t.timestamps
    end

    # ses_message_id is the join key for SNS event correlation — must be
    # unique so a duplicate SES delivery never collides into the wrong row.
    # We allow many NULLs (stub mode + failed sends), which Postgres + SQLite
    # both handle natively under a partial / standard unique index.
    add_index :deliveries, :ses_message_id, unique: true
    add_index :deliveries, [:campaign_id, :status]
  end
end
