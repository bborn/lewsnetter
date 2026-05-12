class AddConfigurationSetToTeamSesConfigurations < ActiveRecord::Migration[8.1]
  # SES won't publish bounce/complaint events unless each `SendEmail` call
  # references a configuration set wired up with event destinations. We default
  # every tenant to the shared `lewsnetter-default` set we provision in IK's
  # AWS account, but the column is per-team so a tenant bringing their own
  # AWS account can point at their own set later.
  def change
    add_column :team_ses_configurations, :configuration_set_name, :string,
      default: "lewsnetter-default"
  end
end
