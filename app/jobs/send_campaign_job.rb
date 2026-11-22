# Sends a Campaign: transitions draft -> sending, batches subscribers 50 at a
# time, calls SesSender, and updates campaign.stats. On completion we set
# status=sent + sent_at. On invalid predicate we set status=failed and record
# the error in campaign.stats["errors"] without re-raising. On any other
# unexpected exception we set status=failed and re-raise so the queue retries
# / surfaces the failure.
#
# Resume: `perform(id, resume: true)` picks up a failed or stuck send (see
# Campaign#resumable?). Every send, fresh or resumed, skips subscribers who
# already have a Delivery for the campaign, and the unique index on
# deliveries(campaign_id, subscriber_id) backs that up, so nobody is mailed
# the same broadcast twice.
class SendCampaignJob < ApplicationJob
  BATCH_SIZE = 50

  queue_as :default

  def perform(campaign_id, resume: false, from_scheduler: false)
    campaign = Campaign.find(campaign_id)

    unless claim_campaign(campaign, resume: resume, from_scheduler: from_scheduler)
      Rails.logger.warn("[SendCampaignJob] Campaign #{campaign.id} is in status=#{campaign.status}; skipping.")
      return
    end

    recipients =
      begin
        audience_for(campaign)
      rescue Segment::InvalidPredicate => e
        Rails.logger.error("[SendCampaignJob] #{e.message}")
        record_failure(campaign, e.message)
        return
      end

    # A resume keeps counting from where the interrupted run left off; a
    # fresh send was reset to zero by the claim.
    sent_count = campaign.stats["sent"].to_i
    failed_count = campaign.stats["failed"].to_i
    suppressed_count = campaign.stats["suppressed"].to_i
    duplicate_count = campaign.stats["duplicates"].to_i
    errors = Array(campaign.stats["errors"])

    # One address, one send. A person can exist as multiple subscriber rows
    # (the sync keys on external_id, not email, so duplicate source records
    # become duplicate rows sharing an address). De-dupe by normalized email
    # across the whole send so nobody is emailed twice. find_in_batches yields
    # in ascending id order, so the oldest row for an address wins.
    #
    # On a resume, addresses already sent to by an earlier run count as seen,
    # so a second subscriber row sharing one of them is skipped too.
    seen_emails = Set.new
    Subscriber.where(id: campaign.deliveries.select(:subscriber_id)).find_each do |subscriber|
      seen_emails << subscriber.email.to_s.strip.downcase
    end

    recipients.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      unique_batch = []
      batch.each do |subscriber|
        key = subscriber.email.to_s.strip.downcase
        next if key.blank?
        if seen_emails.add?(key)
          unique_batch << subscriber
        else
          duplicate_count += 1
        end
      end

      if unique_batch.any?
        result = SesSender.send_bulk(campaign: campaign, subscribers: unique_batch)
        sent_count += result.message_ids.size
        failed_count += result.failed.size
        suppressed_count += result.suppressed.size
        duplicate_count += Array(result.already_delivered).size
        errors.concat(result.failed.map { |f| "#{f[:subscriber]&.email}: #{f[:error]}" })

        bump_last_contacted!(unique_batch, result)
      end

      stats = campaign.stats.dup
      stats["sent"] = sent_count
      stats["failed"] = failed_count
      stats["suppressed"] = suppressed_count
      stats["duplicates"] = duplicate_count
      stats["errors"] = errors
      campaign.update_column(:stats, stats)
    end

    campaign.update!(status: "sent", sent_at: Time.current)
  rescue ActiveRecord::StatementInvalid => e
    # The predicate passed our allowlist but Postgres rejected it (bad column
    # name, syntax error, etc). Capture it as a failure rather than crashing
    # the worker — the user can edit the segment and retry.
    Rails.logger.error("[SendCampaignJob] Predicate failed in DB: #{e.message}")
    if campaign
      record_failure(campaign, "Predicate failed in DB: #{e.message.split("\n").first}")
    end
  rescue => e
    Rails.logger.error("[SendCampaignJob] Failed to send campaign #{campaign_id}: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace
    Campaign.where(id: campaign_id).update_all(status: "failed")
    raise
  end

  private

  # Row lock so overlapping scheduler ticks, a manual Send and a Resume
  # can't all start the same campaign. A resume also stamps updated_at,
  # which keeps a second resume out until this run goes quiet again.
  def claim_campaign(campaign, resume:, from_scheduler:)
    campaign.with_lock do
      if resume
        next false unless campaign.resumable?

        campaign.update!(status: "sending", updated_at: Time.current)
      elsif from_scheduler
        next false unless scheduler_sendable?(campaign)

        campaign.update!(status: "sending", stats: campaign.stats.merge("sent" => 0, "failed" => 0, "suppressed" => 0, "duplicates" => 0, "errors" => []))
      else
        next false unless campaign.sendable?

        campaign.update!(status: "sending", stats: campaign.stats.merge("sent" => 0, "failed" => 0, "suppressed" => 0, "duplicates" => 0, "errors" => []))
      end
      true
    end
  end

  # Jobs enqueued by ScheduledCampaignDispatchJob carry scheduling intent;
  # re-check it under the claim lock so a stale queue entry can't send early
  # or after the user cancelled, postponed or narrowed the audience.
  def scheduler_sendable?(campaign)
    return false unless campaign.scheduled?
    return false if campaign.scheduled_for.blank? || campaign.scheduled_for > Time.current
    return false if campaign.segment_id.nil? && !campaign.all_subscribers_confirmed?

    true
  end

  # The campaign's audience minus anyone who already has a Delivery for it.
  # Predicate validation lives on Segment#applies_to.
  def audience_for(campaign)
    campaign.unsent_audience
  end

  def record_failure(campaign, message)
    stats = campaign.stats.dup
    stats["errors"] = (stats["errors"] || []) + [message]
    campaign.update!(status: "failed", stats: stats)
  end

  # Stamp `last_contacted_at` + bump `times_contacted` for everyone in the
  # batch that SES accepted. Powers the "contacted in last N days" /
  # "never contacted" segment filters. One UPDATE per batch — cheap.
  # Test sends don't come through this job, so they don't bump the counter
  # (which is the right call — a test send isn't a real campaign contact).
  def bump_last_contacted!(batch, result)
    failed_ids = result.failed.map { |f| f[:subscriber]&.id }.compact.to_set
    # Suppressed subscribers had no actual send — don't bump their
    # contact recency, otherwise "never contacted" segments stop matching
    # someone who's been on the blocklist the whole time.
    suppressed_ids = result.suppressed.map(&:id).to_set
    skip_ids = failed_ids | suppressed_ids
    succeeded_ids = batch.map(&:id).reject { |id| skip_ids.include?(id) }
    return if succeeded_ids.empty?

    Subscriber.where(id: succeeded_ids).update_all([
      "last_contacted_at = ?, times_contacted = COALESCE(times_contacted, 0) + 1",
      Time.current
    ])
  end
end
