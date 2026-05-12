class CreateTeamSesConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :team_ses_configurations do |t|
      t.references :team, null: false, foreign_key: true, type: :integer, index: {unique: true}

      # Encrypted at rest via Rails 7+ `encrypts`. The column names keep the
      # `encrypted_` prefix as a reminder that ciphertext is what's written
      # to disk — but `encrypts` makes reads return plaintext transparently.
      t.string :encrypted_access_key_id
      t.string :encrypted_secret_access_key
      t.string :region, null: false, default: "us-east-1"

      # The SNS topic ARNs in the tenant's AWS account where they configure
      # SES to publish bounce + complaint events. We use these to route inbound
      # webhook traffic back to the right team.
      t.string :sns_bounce_topic_arn
      t.string :sns_complaint_topic_arn

      # Status tracked via aws ses get-account + list-email-identities.
      t.string :status, null: false, default: "unconfigured"
      t.integer :quota_max_send_24h
      t.integer :quota_sent_last_24h
      t.boolean :sandbox, null: false, default: true
      t.datetime :last_verified_at

      t.timestamps
    end

    # Lookup by SNS topic ARN must be fast — webhook latency matters.
    add_index :team_ses_configurations, :sns_bounce_topic_arn, where: "sns_bounce_topic_arn IS NOT NULL"
    add_index :team_ses_configurations, :sns_complaint_topic_arn, where: "sns_complaint_topic_arn IS NOT NULL"
  end
end
