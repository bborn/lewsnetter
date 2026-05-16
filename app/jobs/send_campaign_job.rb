# Sends a Campaign: transitions draft -> sending, batches subscribers 50 at a
# time, calls SesSender, and updates campaign.stats. On completion we set
# status=sent + sent_at. On invalid predicate we set status=failed and record
# the error in campaign.stats["errors"] without re-raising. On any other
# unexpected exception we set status=failed and re-raise so the queue retries
# / surfaces the failure.
class SendCampaignJob < ApplicationJob
  BATCH_SIZE = 50

  queue_as :default

  def perform(campaign_id)
    campaign = Campaign.find(campaign_id)

    unless campaign.status.in?(%w[draft scheduled])
      Rails.logger.warn("[SendCampaignJob] Campaign #{campaign.id} is in status=#{campaign.status}; skipping.")
      return
    end

    campaign.update!(status: "sending", stats: campaign.stats.merge("sent" => 0, "failed" => 0, "errors" => []))

    recipients =
      begin
        audience_for(campaign)
      rescue Segment::InvalidPredicate => e
        Rails.logger.error("[SendCampaignJob] #{e.message}")
        record_failure(campaign, e.message)
        return
      end

    sent_count = 0
    failed_count = 0
    errors = []

    recipients.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      result = SesSender.send_bulk(campaign: campaign, subscribers: batch)
      sent_count += result.message_ids.size
      failed_count += result.failed.size
      errors.concat(result.failed.map { |f| "#{f[:subscriber]&.email}: #{f[:error]}" })

      bump_last_contacted!(batch, result)

      stats = campaign.stats.dup
      stats["sent"] = sent_count
      stats["failed"] = failed_count
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

  # Apply the team-wide subscribed scope, then narrow by segment predicate
  # if one is attached. Predicate validation lives on Segment#applies_to.
  def audience_for(campaign)
    scope = campaign.team.subscribers.subscribed
    return scope unless campaign.segment

    campaign.segment.applies_to(scope)
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
    succeeded_ids = batch.map(&:id).reject { |id| failed_ids.include?(id) }
    return if succeeded_ids.empty?

    Subscriber.where(id: succeeded_ids).update_all([
      "last_contacted_at = ?, times_contacted = COALESCE(times_contacted, 0) + 1",
      Time.current
    ])
  end
end
