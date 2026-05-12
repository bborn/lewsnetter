class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      t.references :team, null: false, foreign_key: true, type: :integer
      t.references :email_template, foreign_key: true
      t.references :segment, foreign_key: true

      # SenderAddress model is added with the SES integration commit; reserve
      # the FK column so we don't need a schema change at that point.
      t.integer :sender_address_id

      t.string :subject
      t.string :preheader
      t.text :body_mjml
      t.text :body_html

      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_for
      t.datetime :sent_at

      t.jsonb :stats, null: false, default: {}

      t.timestamps
    end

    add_index :campaigns, [:team_id, :status]
    add_index :campaigns, [:team_id, :scheduled_for]
    add_index :campaigns, :sender_address_id
  end
end
