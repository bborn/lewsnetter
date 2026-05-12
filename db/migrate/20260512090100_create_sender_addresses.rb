class CreateSenderAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :sender_addresses do |t|
      t.references :team, null: false, foreign_key: true
      t.string :email
      t.string :name
      t.boolean :verified, default: false
      t.string :ses_status

      t.timestamps
    end
  end
end
