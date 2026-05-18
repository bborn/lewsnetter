# Collected during the SES setup wizard for CAN-SPAM compliance. Every
# commercial email's footer must include the sender's physical postal
# address; we'll auto-inject this into campaign templates later. For now
# we just collect + store. Optional column — old rows stay valid.
class AddPhysicalPostalAddressToTeamSesConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_ses_configurations, :physical_postal_address, :text
  end
end
