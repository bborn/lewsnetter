class AddEmailDomainToSubscribers < ActiveRecord::Migration[8.0]
  # Plaintext, indexable copy of the email's domain. `email` itself is
  # encrypted (deterministic), so substring/domain filtering against it is
  # impossible at the SQL layer. Materializing just the domain lets segments
  # filter by it (e.g. everyone @acme.com) while the full address stays
  # encrypted. Populated by Subscriber#set_email_domain on every save; backfill
  # existing rows with `rails subscribers:backfill_email_domains`.
  def change
    add_column :subscribers, :email_domain, :string
    add_index :subscribers, [:team_id, :email_domain]
  end
end
