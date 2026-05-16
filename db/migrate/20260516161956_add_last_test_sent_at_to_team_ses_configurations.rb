# Records when the team last fired a self-test through SES (the final step
# of the SES setup wizard). Used to detect a completed setup so the
# dashboard onboarding banner can disappear and the wizard knows to bail
# out to the management view.
class AddLastTestSentAtToTeamSesConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_ses_configurations, :last_test_sent_at, :datetime
  end
end
