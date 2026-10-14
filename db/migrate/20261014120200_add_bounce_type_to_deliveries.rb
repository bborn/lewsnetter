class AddBounceTypeToDeliveries < ActiveRecord::Migration[8.0]
  # SES bounces carry two fields: `bounceType` (Permanent / Transient /
  # Undetermined) and `bounceSubType` (MailboxFull, General, NoEmail,
  # ContentRejected…). Until now the SNS handler wrote bounceType into
  # `bounce_subtype`, so the real subtype was lost. New rows store both.
  #
  # Existing rows: anything in bounce_subtype that is actually a bounceType
  # value is moved to bounce_type, and bounce_subtype is cleared (the real
  # subtype was never recorded for those rows, so it stays unknown).
  BOUNCE_TYPES = %w[Permanent Transient Undetermined].freeze

  def up
    add_column :deliveries, :bounce_type, :string

    quoted = BOUNCE_TYPES.map { |t| connection.quote(t) }.join(", ")
    execute <<~SQL
      UPDATE deliveries
      SET bounce_type = bounce_subtype, bounce_subtype = NULL
      WHERE bounce_subtype IN (#{quoted})
    SQL
  end

  def down
    execute <<~SQL
      UPDATE deliveries
      SET bounce_subtype = bounce_type
      WHERE bounce_type IS NOT NULL
    SQL
    remove_column :deliveries, :bounce_type
  end
end
