class AddSenderAddressFkToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :campaigns, :sender_addresses
  end
end
