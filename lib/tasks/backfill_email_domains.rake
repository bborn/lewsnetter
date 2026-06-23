namespace :subscribers do
  desc "Backfill email_domain on existing subscribers (decrypts email in Ruby; idempotent)"
  task backfill_email_domains: :environment do
    scope = Subscriber.where(email_domain: nil)
    total = scope.count
    puts "Backfilling email_domain for #{total} subscriber(s) with a NULL domain..."

    updated = 0
    skipped = 0
    scope.find_each(batch_size: 1000) do |subscriber|
      domain = subscriber.email.to_s.split("@", 2)[1]&.downcase
      if domain.nil?
        skipped += 1
        next
      end
      # update_columns: skip callbacks/validations and don't bump updated_at,
      # so a backfill doesn't look like subscriber activity.
      subscriber.update_columns(email_domain: domain)
      updated += 1
      puts "  ...#{updated} updated" if (updated % 1000).zero?
    end

    puts "Done. #{updated} updated, #{skipped} skipped (no @ in address)."
  end
end
