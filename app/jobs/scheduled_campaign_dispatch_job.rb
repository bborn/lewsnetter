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
class ScheduledCampaignDispatchJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Campaign.due_for_sending(now)
      .order(:scheduled_for)
      .pluck(:id)
      .each { |id| SendCampaignJob.perform_later(id) }
  end
end
