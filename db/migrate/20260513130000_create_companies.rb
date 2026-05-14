class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.references :team, null: false, foreign_key: true, type: :integer

      t.string :name, null: false
      t.string :external_id
      t.string :intercom_id
      t.json :custom_attributes, default: {}, null: false

      t.timestamps
    end

    add_index :companies, [:team_id, :external_id],
      unique: true, where: "external_id IS NOT NULL",
      name: "index_companies_on_team_id_and_external_id"
    add_index :companies, [:team_id, :intercom_id],
      unique: true, where: "intercom_id IS NOT NULL",
      name: "index_companies_on_team_id_and_intercom_id"
  end
end
