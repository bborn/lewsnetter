# Set when a campaign with no segment is scheduled with an explicit
# all_subscribers confirmation (campaigns_schedule's all_subscribers: true).
# ScheduledCampaignDispatchJob won't send a due campaign that has no segment
# unless this is true, so nothing reaches every subscriber by accident.
class AddAllSubscribersConfirmedToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :all_subscribers_confirmed, :boolean, default: false, null: false
  end
end
