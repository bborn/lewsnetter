class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.references :team, null: false, foreign_key: true, type: :integer

      t.string :name, null: false
      t.text :mjml_body
      t.text :rendered_html

      t.timestamps
    end

    add_index :templates, [:team_id, :name]
  end
end
