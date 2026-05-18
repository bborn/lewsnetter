class Avo::Resources::TeamSesDomain < Avo::BaseResource
  self.model_class = ::Team::SesDomain
  self.title = :domain
  self.includes = [:team]
  self.search = {
    query: -> {
      query.ransack(id_eq: params[:q], domain_cont: params[:q], m: "or").result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :domain, as: :text
    field :status, as: :select, options: ::Team::SesDomain::STATUSES.index_by(&:itself)
    field :verification_status, as: :text, hide_on: :index
    field :dkim_status, as: :text, hide_on: :index
    field :dkim_tokens, as: :textarea, hide_on: :index
    field :verified_at, as: :date_time, readonly: true
    field :last_checked_at, as: :date_time, readonly: true
    field :last_verification_requested_at, as: :date_time, readonly: true
    field :created_at, as: :date_time, readonly: true, hide_on: :forms
  end
end
