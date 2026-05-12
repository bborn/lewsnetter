class AddDeviseTwoFactorBackupableToUsers < ActiveRecord::Migration[6.0]
  def change
    # On Postgres this was `:string, array: true`. SQLite has no native
    # array type, so we store the codes as JSON. devise-two-factor reads
    # the column as a plain attribute, so serialize_as: :json on the
    # User model (or a `serialize :otp_backup_codes, Array`) keeps the
    # behavior identical from Ruby's side.
    add_column :users, :otp_backup_codes, :json
  end
end
