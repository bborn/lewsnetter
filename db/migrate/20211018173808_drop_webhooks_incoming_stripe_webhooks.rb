class DropWebhooksIncomingStripeWebhooks < ActiveRecord::Migration[6.1]
  def change
    drop_table :webhooks_incoming_stripe_webhooks do |t|
      t.json :data
      t.datetime :processed_at
      t.datetime :verified_at

      t.timestamps
    end
  end
end
