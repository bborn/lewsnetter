class AddUnsubscribeHostToTeamSesConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_ses_configurations, :unsubscribe_host, :string
  end
end
