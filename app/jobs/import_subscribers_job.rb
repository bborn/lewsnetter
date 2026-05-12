require "csv"

# Streams a CSV file attached to a Subscribers::Import and upserts each row
# as a Subscriber on the import's team. Idempotent: looks up by external_id
# when present, otherwise by email. Per-row validation errors are captured
# in the import's errors_log rather than aborting the run. Progress is
# flushed to the import record every PROGRESS_INTERVAL rows so the UI can
# show live counts.
#
# Recognized headers (case-insensitive): external_id, email, name,
# subscribed. Any other header is folded into the subscriber's
# custom_attributes JSON column.
class ImportSubscribersJob < ApplicationJob
  queue_as :default

  PROGRESS_INTERVAL = 100
  KNOWN_FIELDS = %w[external_id email name subscribed].freeze
  MAX_ERRORS_LOGGED = 100

  def perform(import_id)
    import = Subscribers::Import.find(import_id)

    unless import.csv.attached?
      import.update_columns(
        status: "failed",
        notes: "No CSV attachment found.",
        finished_at: Time.current
      )
      return
    end

    import.update_columns(status: "processing", started_at: Time.current,
      processed: 0, created_count: 0, updated_count: 0, error_count: 0,
      errors_log: [])

    created = 0
    updated = 0
    errors = 0
    processed = 0
    errors_log = []

    import.csv.open do |tempfile|
      CSV.foreach(tempfile.path, headers: true, header_converters: :downcase) do |row|
        processed += 1
        result = upsert_row(import.team, row)

        case result[:outcome]
        when :created then created += 1
        when :updated then updated += 1
        when :error
          errors += 1
          if errors_log.size < MAX_ERRORS_LOGGED
            errors_log << {row: processed, email: result[:email], errors: result[:errors]}
          end
        end

        if (processed % PROGRESS_INTERVAL).zero?
          import.update_columns(
            processed: processed,
            created_count: created,
            updated_count: updated,
            error_count: errors,
            errors_log: errors_log
          )
        end
      end
    end

    import.update_columns(
      status: "completed",
      processed: processed,
      total_rows: processed,
      created_count: created,
      updated_count: updated,
      error_count: errors,
      errors_log: errors_log,
      finished_at: Time.current
    )
  rescue => e
    Rails.logger.error("[ImportSubscribersJob] Failed import #{import_id}: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace
    Subscribers::Import.where(id: import_id).update_all(
      status: "failed",
      notes: "#{e.class}: #{e.message}",
      finished_at: Time.current
    )
    raise
  end

  private

  # Find-or-initialize the Subscriber, assign mapped attributes, save.
  # Returns {outcome: :created|:updated|:error, email:, errors:}.
  def upsert_row(team, row)
    external_id = row["external_id"].presence
    email = row["email"]&.strip.presence

    subscriber =
      if external_id
        team.subscribers.find_or_initialize_by(external_id: external_id)
      elsif email
        team.subscribers.find_or_initialize_by(email: email)
      else
        return {outcome: :error, email: nil, errors: ["missing external_id and email"]}
      end

    was_new = subscriber.new_record?

    # Always update email if provided (e.g. the row is keyed by external_id
    # but the email has changed in the source system).
    subscriber.email = email if email
    subscriber.name = row["name"] if row.headers.include?("name")
    subscriber.external_id = external_id if external_id && subscriber.external_id.blank?

    if row.headers.include?("subscribed")
      subscriber.subscribed = parse_boolean(row["subscribed"])
    end

    # Anything that isn't a known top-level field gets folded into
    # custom_attributes. Existing custom_attributes are preserved and merged.
    custom = subscriber.custom_attributes || {}
    row.headers.each do |header|
      next if header.nil?
      next if KNOWN_FIELDS.include?(header)
      value = row[header]
      next if value.nil?
      custom[header] = value
    end
    subscriber.custom_attributes = custom

    if subscriber.save
      {outcome: was_new ? :created : :updated, email: subscriber.email, errors: []}
    else
      {outcome: :error, email: subscriber.email, errors: subscriber.errors.full_messages}
    end
  rescue => e
    {outcome: :error, email: email, errors: ["#{e.class}: #{e.message}"]}
  end

  def parse_boolean(value)
    return true if value.nil? # default to subscribed
    %w[true 1 yes y t].include?(value.to_s.strip.downcase)
  end
end
