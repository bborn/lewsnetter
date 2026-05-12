class CreateWebhooksIncomingStripeWebhooks < ActiveRecord::Migration[5.2]
  def change
    create_table :webhooks_incoming_stripe_webhooks do |t|
      t.json :data
      t.datetime :processed_at
      t.datetime :verified_at

      t.timestamps
    end
  end
end
