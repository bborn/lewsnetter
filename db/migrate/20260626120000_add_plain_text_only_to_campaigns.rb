class AddPlainTextOnlyToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :plain_text_only, :boolean, default: false, null: false
  end
end
