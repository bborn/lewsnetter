# One-time migration tasks for moving audiences into Lewsnetter from
# external systems. These are intentionally simple, single-purpose, and
# safe to re-run (idempotent on external_id).
#
# Usage:
#   INTERCOM_TOKEN=tok_... TEAM_ID=1 bin/rails migrations:import_from_intercom
#
# Optional:
#   DRY_RUN=true            # iterate without writing
#   MAX_PAGES=10            # cap pagination for a smoke test
#   INTERCOM_VERSION=2.12   # Intercom-Version header (default 2.12)

require "net/http"
require "json"
require "uri"

namespace :migrations do
  desc "Import contacts from Intercom into Lewsnetter via the Contacts API"
  task import_from_intercom: :environment do
    token = ENV.fetch("INTERCOM_TOKEN") { abort "Set INTERCOM_TOKEN (Intercom Access Token)" }
    team_id = Integer(ENV.fetch("TEAM_ID", "1"))
    dry_run = ENV.fetch("DRY_RUN", "false") == "true"
    max_pages = ENV["MAX_PAGES"]&.to_i
    api_version = ENV.fetch("INTERCOM_VERSION", "2.12")

    team = Team.find(team_id)
    puts "Importing Intercom contacts → Team ##{team.id} (#{team.name})"
    puts dry_run ? "DRY RUN — no writes." : "LIVE RUN — will upsert subscribers."
    puts

    page = 0
    processed = 0
    created = 0
    updated = 0
    skipped_no_email = 0
    errors = []
    starting_after = nil

    loop do
      page += 1
      break if max_pages && page > max_pages

      response = intercom_search(token: token, api_version: api_version, starting_after: starting_after)
      contacts = response.fetch("data", [])
      next_cursor = response.dig("pages", "next", "starting_after")

      puts "Page #{page}: #{contacts.size} contacts (cursor → #{next_cursor.to_s[0, 8] || "(end)"})"

      contacts.each do |c|
        processed += 1
        email = c["email"].to_s.strip.downcase
        if email.blank?
          skipped_no_email += 1
          next
        end

        external_id = c["external_id"].presence || c["id"]
        custom_attrs = c["custom_attributes"] || {}
        unsubscribed = c["unsubscribed_from_emails"] == true
        bounced = c["marked_email_as_spam"] == true || c["has_hard_bounced"] == true
        subscribed = !unsubscribed && !bounced

        attrs = {
          email: email,
          external_id: external_id.to_s,
          name: c["name"],
          subscribed: subscribed,
          custom_attributes: custom_attrs.merge(
            "intercom_id" => c["id"],
            "intercom_role" => c["role"],
            "intercom_last_seen_at" => c["last_seen_at"],
            "intercom_signed_up_at" => c["signed_up_at"]
          ).compact
        }

        # Track bounced state on the Lewsnetter side too — preserves the
        # "don't email" signal across the migration even though `subscribed`
        # is the active filter.
        attrs[:bounced_at] = Time.current if bounced && !attrs[:bounced_at]

        if dry_run
          # Just count the would-be result
          existing = team.subscribers.find_by(external_id: external_id) ||
            team.subscribers.find_by(email: email)
          existing ? (updated += 1) : (created += 1)
          next
        end

        begin
          existing = team.subscribers.find_by(external_id: external_id) ||
            team.subscribers.find_by(email: email)

          if existing
            existing.update!(attrs)
            updated += 1
          else
            team.subscribers.create!(attrs)
            created += 1
          end
        rescue ActiveRecord::RecordInvalid => e
          errors << {contact_id: c["id"], email: email, error: e.message}
        rescue => e
          errors << {contact_id: c["id"], email: email, error: "#{e.class}: #{e.message}"}
        end

        if (processed % 500).zero?
          puts "  ... #{processed} processed (#{created} created, #{updated} updated, #{errors.size} errors)"
        end
      end

      break if next_cursor.blank?
      starting_after = next_cursor
    end

    puts
    puts "Done."
    puts "Pages walked: #{page}"
    puts "Contacts processed: #{processed}"
    puts "Created: #{created}"
    puts "Updated: #{updated}"
    puts "Skipped (no email): #{skipped_no_email}"
    puts "Errors: #{errors.size}"
    if errors.any?
      puts
      puts "First 10 errors:"
      errors.first(10).each { |e| puts "  - #{e[:email] || e[:contact_id]}: #{e[:error]}" }
    end
  end

  def intercom_search(token:, api_version:, starting_after: nil)
    uri = URI("https://api.intercom.io/contacts/search")
    body = {
      query: {field: "role", operator: "=", value: "user"},
      pagination: {per_page: 150}
    }
    body[:pagination][:starting_after] = starting_after if starting_after

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    request["Content-Type"] = "application/json"
    request["Intercom-Version"] = api_version
    request.body = body.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
      http.request(request)
    end

    if response.code.to_i >= 400
      abort "Intercom API error #{response.code}: #{response.body[0, 500]}"
    end

    JSON.parse(response.body)
  end
end
