class CreateTemplates < ActiveRecord::Migration
  def change
    add_column :mail_campaigns, :template_id, :integer

    create_table :templates do |t|
      t.string :name
      t.text :html

      t.timestamps
    end
  end
end
