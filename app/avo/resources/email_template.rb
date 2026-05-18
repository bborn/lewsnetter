class Avo::Resources::EmailTemplate < Avo::BaseResource
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
    field :mjml_body, as: :code, language: "xml", hide_on: :index
    field :rendered_html, as: :code, language: "html", hide_on: :index
    field :created_at, as: :date_time, readonly: true, hide_on: :forms

    field :campaigns, as: :has_many
  end
end
