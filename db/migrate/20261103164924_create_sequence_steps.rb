class CreateSequenceSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :sequence_steps do |t|
      t.references :sequence, null: false, foreign_key: true, type: :integer
      t.integer :position, null: false, default: 0

      # Minutes to wait after the previous step (or after enrollment, for the
      # first step) before this one sends.
      t.integer :delay_minutes, null: false, default: 0

      t.string :subject
      t.string :preheader
      t.text :body_markdown
      t.references :email_template, foreign_key: {on_delete: :nullify}, type: :integer

      # Subscribers matching this segment skip the step (the sequence still
      # moves on to the next one).
      t.references :skip_segment, foreign_key: {to_table: :segments, on_delete: :nullify}, type: :integer

      # Hidden backing Campaign (status "sequence"). Deliveries hang off it so
      # SES webhooks, tracking, unsubscribe links and delivery_stats work
      # exactly as they do for one-off campaigns.
      t.references :campaign, foreign_key: {on_delete: :nullify}, type: :integer

      t.integer :skipped_count, null: false, default: 0

      t.timestamps
    end

    add_index :sequence_steps, [:sequence_id, :position]
  end
end
