class AddBodyMarkdownToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :body_markdown, :text
  end
end
