class AddSnsDeliveryTopicArnToTeamSesConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_ses_configurations, :sns_delivery_topic_arn, :string
    add_index :team_ses_configurations, :sns_delivery_topic_arn,
      where: "sns_delivery_topic_arn IS NOT NULL"
  end
end
