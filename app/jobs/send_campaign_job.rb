# Sends a Campaign: transitions draft -> sending, batches subscribers 50 at a
# time, calls SesSender, and updates campaign.stats. On completion we set
# status=sent + sent_at. On exception we set status=failed and re-raise.
class SendCampaignJob < ApplicationJob
  BATCH_SIZE = 50

  queue_as :default

  def perform(campaign_id)
    campaign = Campaign.find(campaign_id)

    unless campaign.status.in?(%w[draft scheduled])
      Rails.logger.warn("[SendCampaignJob] Campaign #{campaign.id} is in status=#{campaign.status}; skipping.")
      return
    end

    campaign.update!(status: "sending", stats: campaign.stats.merge("sent" => 0, "failed" => 0))

    recipients = audience_for(campaign)
    sent_count = 0
    failed_count = 0

    recipients.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      result = SesSender.send_bulk(campaign: campaign, subscribers: batch)
      sent_count += result.message_ids.size
      failed_count += result.failed.size

      stats = campaign.stats.dup
      stats["sent"] = sent_count
      stats["failed"] = failed_count
      campaign.update_column(:stats, stats)
    end

    campaign.update!(status: "sent", sent_at: Time.current)
  rescue => e
    Rails.logger.error("[SendCampaignJob] Failed to send campaign #{campaign_id}: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace
    Campaign.where(id: campaign_id).update_all(status: "failed")
    raise
  end

  private

  # MVP audience: all subscribed subscribers on the team. Segment-predicate
  # evaluation lives in Stream D; if a segment is attached we still send to
  # the whole team for now.
  def audience_for(campaign)
    campaign.team.subscribers.subscribed
  end
end
