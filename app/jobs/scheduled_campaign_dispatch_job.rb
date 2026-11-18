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
# Otherwise it stays scheduled and is logged on each tick until someone adds
# a segment or reschedules it with the confirmation.
class ScheduledCampaignDispatchJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Campaign.due_for_sending(now)
      .order(:scheduled_for)
      .pluck(:id, :segment_id, :all_subscribers_confirmed)
      .each do |id, segment_id, all_subscribers_confirmed|
        if segment_id.nil? && !all_subscribers_confirmed
          Rails.logger.warn(
            "[ScheduledCampaignDispatchJob] Campaign #{id} is due but has no segment and wasn't " \
            "scheduled for all subscribers; not sending."
          )
          next
        end

        SendCampaignJob.perform_later(id)
      end
  end
end
