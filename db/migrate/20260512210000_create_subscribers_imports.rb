class CreateSubscribersImports < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers_imports do |t|
      t.references :team, null: false, foreign_key: true, type: :integer

      t.string :status, null: false, default: "pending"
      t.integer :total_rows
      t.integer :processed, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.json :errors_log, null: false, default: []
      t.text :notes

      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :subscribers_imports, [:team_id, :created_at]
  end
end
