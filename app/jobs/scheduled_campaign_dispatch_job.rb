# Every minute (config/recurring.yml): hand each scheduled campaign whose
# scheduled_for has passed to SendCampaignJob, across all teams.
#
# SendCampaignJob claims the campaign under a row lock and only proceeds
# while it is still draft/scheduled, so overlapping ticks, or a tick racing
# a manual Send, enqueue harmless extra jobs that skip.
#
# A campaign whose time passed while the app was down goes out on the first
# tick after it comes back: scheduled_for is "send no earlier than", not
# "send only at".
#
# A due campaign with no segment would go to every subscribed contact. It is
# only sent when it was scheduled with all_subscribers confirmed
# (campaigns_schedule's all_subscribers: true sets all_subscribers_confirmed).
# Otherwise it goes back to draft with scheduled_for cleared and the reason
# in unscheduled_reason, which the campaign page shows.
class ScheduledCampaignDispatchJob < ApplicationJob
  queue_as :default

  UNCONFIRMED_REASON = "This campaign was scheduled without a segment and without confirming it should go to " \
    "every subscribed contact, so it wasn't sent. Add a segment, or schedule it again for all subscribers."

  def perform(now: Time.current)
    Campaign.due_for_sending(now).order(:scheduled_for).each do |campaign|
      if campaign.audience_confirmed?
        SendCampaignJob.perform_later(campaign.id, from_scheduler: true)
      else
        unschedule(campaign)
      end
    end
  end

  private

  # Under the row lock so a manual Send that already claimed it wins.
  def unschedule(campaign)
    campaign.with_lock do
      next unless campaign.scheduled? && !campaign.audience_confirmed?

      campaign.update!(status: "draft", scheduled_for: nil, unscheduled_reason: UNCONFIRMED_REASON)
    end
    Rails.logger.warn("[ScheduledCampaignDispatchJob] Campaign #{campaign.id} had no segment and no all-subscribers confirmation; moved back to draft.")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[ScheduledCampaignDispatchJob] Couldn't move campaign #{campaign.id} back to draft: #{e.message}")
  end
end
