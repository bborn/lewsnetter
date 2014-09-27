class AddContentJson < ActiveRecord::Migration
  def change
    add_column :mail_campaigns, :content_json, :text
  end
end
