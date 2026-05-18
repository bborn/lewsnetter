class Avo::Resources::Delivery < Avo::BaseResource
  self.includes = [:campaign, :subscriber]
  self.search = {
    query: -> {
      query.ransack(
        id_eq: params[:q],
        ses_message_id_eq: params[:q],
        m: "or"
      ).result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :campaign, as: :belongs_to
    field :subscriber, as: :belongs_to
    field :status, as: :select, options: Delivery::STATUSES.index_by(&:itself)
    field :ses_message_id, as: :text
    field :sent_at, as: :date_time, readonly: true
    field :delivered_at, as: :date_time, readonly: true
    field :bounced_at, as: :date_time, readonly: true
    field :bounce_subtype, as: :text, hide_on: :index
    field :complained_at, as: :date_time, readonly: true
    field :opened_at, as: :date_time, readonly: true
    field :clicked_at, as: :date_time, readonly: true
    field :click_count, as: :number, readonly: true
    field :last_clicked_url, as: :text, hide_on: :index
    field :unsubscribed_at, as: :date_time, readonly: true
    field :error_message, as: :textarea, hide_on: :index
    field :created_at, as: :date_time, readonly: true, hide_on: :forms
  end
end
