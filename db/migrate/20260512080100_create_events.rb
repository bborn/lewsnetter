class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :team, null: false, foreign_key: true, type: :integer
      t.references :subscriber, null: false, foreign_key: true

      t.string :name, null: false
      t.datetime :occurred_at, null: false
      t.json :properties, null: false, default: {}

      t.timestamps
    end

    add_index :events, [:team_id, :name]
    add_index :events, [:team_id, :occurred_at]
    add_index :events, [:subscriber_id, :name]
  end
end
