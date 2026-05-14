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

  desc "Import companies from Intercom into Team#TEAM_ID via /companies/scroll"
  task import_companies_from_intercom: :environment do
    token = ENV.fetch("INTERCOM_TOKEN") { abort "Set INTERCOM_TOKEN (Intercom Access Token)" }
    team_id = Integer(ENV.fetch("TEAM_ID", "1"))
    api_version = ENV.fetch("INTERCOM_VERSION", "2.12")
    dry_run = ENV.fetch("DRY_RUN", "false") == "true"

    team = Team.find(team_id)
    puts "Importing Intercom companies → Team ##{team.id} (#{team.name})"
    puts dry_run ? "DRY RUN — no writes." : "LIVE RUN — will upsert companies."
    puts

    page = 0
    seen = 0
    created = 0
    updated = 0
    errors = []
    starting_after = nil

    loop do
      page += 1
      uri = URI("https://api.intercom.io/companies/scroll")
      uri.query = URI.encode_www_form(starting_after ? {scroll_param: starting_after} : {})
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req["Intercom-Version"] = api_version
      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
      if resp.code.to_i >= 400
        abort "Intercom /companies/scroll error #{resp.code}: #{resp.body[0, 500]}"
      end
      data = JSON.parse(resp.body)
      batch = data["data"] || []
      cursor = data["scroll_param"]

      puts "Page #{page}: #{batch.size} companies (cursor → #{cursor.to_s[0, 8] || "(end)"})"

      batch.each do |co|
        seen += 1
        intercom_id = co["id"].to_s
        external_id = co["company_id"].presence || co["external_id"].presence
        # Intercom returns the customer-supplied external identifier as
        # `company_id` on the company resource (their own internal record id
        # is `id`). Older payload shapes use `external_id`, so check both.
        name = co["name"].presence || "Company #{intercom_id}"
        custom_attrs = co["custom_attributes"] || {}

        attrs = {
          name: name,
          external_id: external_id.to_s.presence,
          intercom_id: intercom_id,
          custom_attributes: custom_attrs
        }

        if dry_run
          existing = team.companies.find_by(intercom_id: intercom_id)
          existing ? (updated += 1) : (created += 1)
          next
        end

        begin
          existing = team.companies.find_by(intercom_id: intercom_id)
          existing ||= team.companies.find_by(external_id: attrs[:external_id]) if attrs[:external_id].present?

          if existing
            existing.update!(attrs)
            updated += 1
          else
            team.companies.create!(attrs)
            created += 1
          end
        rescue ActiveRecord::RecordInvalid => e
          errors << {intercom_id: intercom_id, error: e.message}
        rescue => e
          errors << {intercom_id: intercom_id, error: "#{e.class}: #{e.message}"}
        end

        if (seen % 200).zero?
          puts "  ... #{seen} processed (#{created} created, #{updated} updated, #{errors.size} errors)"
        end
      end

      break if batch.empty? || cursor.blank?
      starting_after = cursor
    end

    puts
    puts "Done."
    puts "Pages walked: #{page}"
    puts "Companies processed: #{seen}"
    puts "Created: #{created}"
    puts "Updated: #{updated}"
    puts "Errors: #{errors.size}"
    if errors.any?
      puts
      puts "First 10 errors:"
      errors.first(10).each { |e| puts "  - #{e[:intercom_id]}: #{e[:error]}" }
    end
  end

  desc "Link Subscribers to Companies by re-fetching each contact's company list"
  task link_subscribers_to_companies: :environment do
    token = ENV.fetch("INTERCOM_TOKEN") { abort "Set INTERCOM_TOKEN" }
    team_id = Integer(ENV.fetch("TEAM_ID", "1"))
    api_version = ENV.fetch("INTERCOM_VERSION", "2.12")
    only_null = ENV.fetch("ONLY_NULL_COMPANY", "false") == "true"
    dry_run = ENV.fetch("DRY_RUN", "false") == "true"

    team = Team.find(team_id)
    puts "Linking subscribers → companies on Team ##{team.id} (#{team.name})"
    puts dry_run ? "DRY RUN — no writes." : "LIVE RUN"
    puts "ONLY_NULL_COMPANY=#{only_null}"
    puts

    # Build a lookup from Intercom company id → local Company id (one query).
    company_lookup = team.companies.where.not(intercom_id: nil).pluck(:intercom_id, :id).to_h
    puts "Loaded #{company_lookup.size} local companies for lookup."
    puts

    scope = team.subscribers
    scope = scope.where(company_id: nil) if only_null
    total = scope.count
    puts "Walking #{total} subscriber(s)..."

    linked = 0
    skipped_no_intercom_id = 0
    skipped_no_company = 0
    skipped_unknown_company = 0
    errors = []

    scope.find_each.with_index(1) do |sub, idx|
      intercom_id = sub.custom_attributes["intercom_id"]
      if intercom_id.blank?
        skipped_no_intercom_id += 1
        next
      end

      uri = URI("https://api.intercom.io/contacts/#{intercom_id}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req["Intercom-Version"] = api_version

      begin
        resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
        if resp.code.to_i >= 400
          errors << {subscriber_id: sub.id, error: "Contact fetch #{resp.code}: #{resp.body[0, 200]}"}
          next
        end
        contact = JSON.parse(resp.body)
        company_ids = (contact.dig("companies", "data") || []).map { |c| c["id"] }
        if company_ids.empty?
          skipped_no_company += 1
          next
        end

        # FIRST company id wins. Brand contacts can technically belong to
        # multiple companies, but per requirements we link to the first.
        first_company_id = company_ids.first
        local_company_id = company_lookup[first_company_id]
        if local_company_id.nil?
          skipped_unknown_company += 1
          next
        end

        if dry_run
          linked += 1
        else
          sub.update_columns(company_id: local_company_id, updated_at: Time.current)
          linked += 1
        end
      rescue => e
        errors << {subscriber_id: sub.id, error: "#{e.class}: #{e.message}"}
      end

      if (idx % 200).zero?
        puts "  ... #{idx}/#{total} processed (linked=#{linked}, no_company=#{skipped_no_company}, unknown_company=#{skipped_unknown_company}, errors=#{errors.size})"
      end

      sleep 0.05 # gentle on Intercom
    end

    puts
    puts "Done."
    puts "Total subscribers walked: #{total}"
    puts "Linked: #{linked}"
    puts "Skipped (no intercom_id): #{skipped_no_intercom_id}"
    puts "Skipped (contact has no company): #{skipped_no_company}"
    puts "Skipped (company id not in local DB): #{skipped_unknown_company}"
    puts "Errors: #{errors.size}"
    if errors.any?
      puts
      puts "First 10 errors:"
      errors.first(10).each { |e| puts "  - sub##{e[:subscriber_id]}: #{e[:error]}" }
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

  desc "Enrich subscribers with tabs_enabled (and other company attrs) from Intercom Companies"
  task enrich_tabs_enabled: :environment do
    token = ENV.fetch("INTERCOM_TOKEN") { abort "Set INTERCOM_TOKEN" }
    team_id = Integer(ENV.fetch("TEAM_ID", "1"))
    api_version = ENV.fetch("INTERCOM_VERSION", "2.12")
    only_tenant_type = ENV["ONLY_TENANT_TYPE"]
    dry_run = ENV.fetch("DRY_RUN", "false") == "true"

    team = Team.find(team_id)
    puts "Enriching subscribers on Team ##{team.id} (#{team.name}) with company.tabs_enabled"
    puts dry_run ? "DRY RUN — no writes." : "LIVE RUN"
    puts

    # Step 1: pull every company in the workspace.
    companies_by_id = {}
    page = 0
    starting_after = nil
    loop do
      page += 1
      uri = URI("https://api.intercom.io/companies/scroll")
      uri.query = URI.encode_www_form(starting_after ? {scroll_param: starting_after} : {})
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req["Intercom-Version"] = api_version
      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
      if resp.code.to_i >= 400
        abort "Intercom /companies/scroll error #{resp.code}: #{resp.body[0, 500]}"
      end
      data = JSON.parse(resp.body)
      batch = data["data"] || []
      batch.each { |c| companies_by_id[c["id"]] = c }
      cursor = data["scroll_param"]
      puts "Companies page #{page}: +#{batch.size} (total #{companies_by_id.size}, cursor → #{cursor.to_s[0, 8] || "(end)"})"
      break if batch.empty? || cursor.blank?
      starting_after = cursor
    end

    puts "Pulled #{companies_by_id.size} companies."
    puts

    # Step 2: walk the target subscribers (optionally filtered by tenant_type).
    scope = team.subscribers
    if only_tenant_type
      scope = scope.where("json_extract(custom_attributes, '$.tenant_type') = ?", only_tenant_type)
    end
    total = scope.count
    puts "Enriching #{total} subscriber(s)#{only_tenant_type ? " with tenant_type=#{only_tenant_type}" : ""}"
    puts

    updated = 0
    skipped_no_intercom_id = 0
    skipped_no_company = 0
    errors = []

    scope.find_each.with_index(1) do |sub, idx|
      intercom_id = sub.custom_attributes["intercom_id"]
      if intercom_id.blank?
        skipped_no_intercom_id += 1
        next
      end

      # Fetch the contact to get its companies list
      uri = URI("https://api.intercom.io/contacts/#{intercom_id}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req["Intercom-Version"] = api_version
      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
      if resp.code.to_i >= 400
        errors << {subscriber_id: sub.id, error: "Contact fetch #{resp.code}: #{resp.body[0, 200]}"}
        next
      end
      contact = JSON.parse(resp.body)
      company_ids = (contact.dig("companies", "data") || []).map { |c| c["id"] }
      if company_ids.empty?
        skipped_no_company += 1
        next
      end

      # Merge tabs_enabled (and the whole company.custom_attributes for now) from each company
      merged_tabs = []
      merged_company_attrs = {}
      company_ids.each do |cid|
        co = companies_by_id[cid]
        next unless co
        attrs = co["custom_attributes"] || {}
        merged_company_attrs.merge!(attrs.transform_keys { |k| "company_#{k}" })
        if attrs["tabs_enabled"].is_a?(String)
          merged_tabs.concat(attrs["tabs_enabled"].split(",").map(&:strip).reject(&:empty?))
        elsif attrs["tabs_enabled"].is_a?(Array)
          merged_tabs.concat(attrs["tabs_enabled"])
        end
      end

      new_attrs = sub.custom_attributes.merge(merged_company_attrs)
      new_attrs["tabs_enabled"] = merged_tabs.uniq.join(",") if merged_tabs.any?

      if dry_run
        updated += 1
        puts "Would update sub##{sub.id} (#{sub.email}): tabs=#{merged_tabs.uniq.inspect} + #{merged_company_attrs.size} company attrs" if idx <= 5
      else
        sub.update!(custom_attributes: new_attrs)
        updated += 1
      end

      if (idx % 50).zero?
        puts "  ... #{idx}/#{total} processed (updated=#{updated}, skipped_no_company=#{skipped_no_company}, errors=#{errors.size})"
      end

      sleep 0.05 # gentle on Intercom (1000 req/min limit; this gives us 20 req/sec headroom)
    end

    puts
    puts "Done."
    puts "Total subscribers walked: #{total}"
    puts "Enriched: #{updated}"
    puts "Skipped (no intercom_id): #{skipped_no_intercom_id}"
    puts "Skipped (no company): #{skipped_no_company}"
    puts "Errors: #{errors.size}"
    if errors.any?
      puts
      puts "First 10 errors:"
      errors.first(10).each { |e| puts "  - sub##{e[:subscriber_id]}: #{e[:error]}" }
    end
  end
end
