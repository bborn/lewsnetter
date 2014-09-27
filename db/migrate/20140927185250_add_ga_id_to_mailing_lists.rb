class AddGaIdToMailingLists < ActiveRecord::Migration
  def change
    add_column :mailing_lists, :google_analytics_id, :string
  end
end
