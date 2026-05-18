class Avo::Resources::TeamSesConfiguration < Avo::BaseResource
  self.model_class = ::Team::SesConfiguration
  self.includes = [:team]

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :region, as: :text
    field :status, as: :select, options: ::Team::SesConfiguration::STATUSES.index_by(&:itself)
    field :sandbox, as: :boolean
    field :configuration_set_name, as: :text, hide_on: :index
    field :unsubscribe_host, as: :text, hide_on: :index
    field :physical_postal_address, as: :textarea, hide_on: :index
    field :sns_bounce_topic_arn, as: :text, hide_on: :index
    field :sns_complaint_topic_arn, as: :text, hide_on: :index
    field :sns_delivery_topic_arn, as: :text, hide_on: :index
    field :quota_max_send_24h, as: :number, readonly: true
    field :quota_sent_last_24h, as: :number, readonly: true
    field :last_verified_at, as: :date_time, readonly: true
    field :last_test_sent_at, as: :date_time, readonly: true
    field :created_at, as: :date_time, readonly: true, hide_on: :forms

    # Encrypted columns intentionally NOT rendered as editable text. Operator
    # rotation goes through Account::EmailSendingController, not Avo.
    field :access_key_id_last_four, as: :text, readonly: true, only_on: :show
  end
end
