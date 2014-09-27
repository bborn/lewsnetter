class CreateSubscriptions < ActiveRecord::Migration
  def change
    create_table :subscriptions do |t|
      t.string :email
      t.string :name
      t.boolean :subscribed
      t.boolean :confirmed
      t.timestamps
    end
  end
end
