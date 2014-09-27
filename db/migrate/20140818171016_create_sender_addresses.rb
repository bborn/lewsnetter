class CreateSenderAddresses < ActiveRecord::Migration
  def change
    create_table :sender_addresses do |t|
      t.string :email
      t.boolean :verified

      t.timestamps
    end
  end
end
