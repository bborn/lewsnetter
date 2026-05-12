class CreateSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers do |t|
      t.references :team, null: false, foreign_key: true, type: :integer

      t.string :external_id
      t.string :email, null: false
      t.string :name

      t.jsonb :custom_attributes, null: false, default: {}

      t.boolean :subscribed, null: false, default: true
      t.datetime :unsubscribed_at
      t.datetime :complained_at
      t.datetime :bounced_at

      t.timestamps
    end

    add_index :subscribers, [:team_id, :external_id], unique: true, where: "external_id IS NOT NULL"
    add_index :subscribers, [:team_id, :email]
    add_index :subscribers, [:team_id, :subscribed]
  end
end
