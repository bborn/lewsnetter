class Avo::Resources::Subscriber < Avo::BaseResource
  self.title = :email
  self.includes = [:team, :company]
  self.search = {
    query: -> {
      query.ransack(
        id_eq: params[:q],
        email_eq: params[:q],
        name_cont: params[:q],
        external_id_eq: params[:q],
        m: "or"
      ).result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :company, as: :belongs_to
    field :email, as: :text
    field :name, as: :text
    field :external_id, as: :text
    field :subscribed, as: :boolean
    field :custom_attributes, as: :code, language: "json", hide_on: :index
    field :last_contacted_at, as: :date_time, readonly: true
    field :times_contacted, as: :number, readonly: true
    field :unsubscribed_at, as: :date_time, readonly: true
    field :bounced_at, as: :date_time, readonly: true
    field :complained_at, as: :date_time, readonly: true
    field :created_at, as: :date_time, readonly: true, hide_on: :forms

    field :deliveries, as: :has_many
    field :events, as: :has_many
  end
end
