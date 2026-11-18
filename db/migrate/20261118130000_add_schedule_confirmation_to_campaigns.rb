# all_subscribers_confirmed: set when a campaign is scheduled with an
# explicit all_subscribers confirmation (campaigns_schedule's
# all_subscribers: true). ScheduledCampaignDispatchJob won't send a due
# campaign that has no segment unless this is true.
#
# unscheduled_reason: why the dispatcher moved a due campaign back to draft
# instead of sending it. Shown on the campaign page; cleared once the
# campaign leaves draft again.
class AddScheduleConfirmationToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :all_subscribers_confirmed, :boolean, default: false, null: false
    add_column :campaigns, :unscheduled_reason, :text
  end
end
