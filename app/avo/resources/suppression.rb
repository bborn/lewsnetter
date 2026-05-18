class Avo::Resources::Suppression < Avo::BaseResource
  self.title = :email
  self.includes = [:team]
  self.search = {
    query: -> {
      query.ransack(id_eq: params[:q], email_eq: params[:q], m: "or").result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :email, as: :text
    field :reason, as: :select, options: Suppression::REASONS.index_by(&:itself)
    field :source, as: :text
    field :note, as: :textarea, hide_on: :index
    field :suppressed_at, as: :date_time, readonly: true
    field :created_at, as: :date_time, readonly: true, hide_on: :forms
  end
end
