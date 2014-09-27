class CreateSubscriptionsMailingLists < ActiveRecord::Migration
  def change
    create_table :mailing_lists_subscriptions, id: false do |t|
      t.references :subscription
      t.references :mailing_list
    end
  end
end
