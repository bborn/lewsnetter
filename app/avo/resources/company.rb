class Avo::Resources::Company < Avo::BaseResource
  self.title = :name
  self.includes = [:team]
  self.search = {
    query: -> {
      query.ransack(
        id_eq: params[:q],
        name_cont: params[:q],
        external_id_eq: params[:q],
        m: "or"
      ).result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :name, as: :text
    field :external_id, as: :text
    field :intercom_id, as: :text
    field :custom_attributes, as: :code, language: "json", hide_on: :index
    field :created_at, as: :date_time, readonly: true, hide_on: :forms

    field :subscribers, as: :has_many
  end
end
