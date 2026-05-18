class Avo::Resources::Segment < Avo::BaseResource
  self.title = :name
  self.includes = [:team]
  self.search = {
    query: -> {
      query.ransack(id_eq: params[:q], name_cont: params[:q], m: "or").result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :name, as: :text
    field :natural_language_source, as: :textarea, hide_on: :index
    field :definition, as: :code, language: "json", hide_on: :index
    field :computed_count, as: :number, readonly: true
    field :last_computed_at, as: :date_time, readonly: true
    field :created_at, as: :date_time, readonly: true, hide_on: :forms

    field :campaigns, as: :has_many
  end
end
