class CreateSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :segments do |t|
      t.references :team, null: false, foreign_key: true, type: :integer

      t.string :name, null: false
      t.jsonb :definition, null: false, default: {}
      t.text :natural_language_source

      t.integer :computed_count
      t.datetime :last_computed_at

      t.timestamps
    end

    add_index :segments, [:team_id, :name]
  end
end
