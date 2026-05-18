class Avo::Resources::Campaign < Avo::BaseResource
  self.title = :subject
  self.includes = [:team, :email_template, :segment, :sender_address]
  self.search = {
    query: -> {
      query.ransack(id_eq: params[:q], subject_cont: params[:q], m: "or").result(distinct: false)
    }
  }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :subject, as: :text
    field :preheader, as: :text, hide_on: :index
    field :status, as: :select, options: Campaign::STATUSES.index_by(&:itself)
    field :email_template, as: :belongs_to
    field :segment, as: :belongs_to
    field :sender_address, as: :belongs_to
    field :scheduled_for, as: :date_time
    field :sent_at, as: :date_time, readonly: true
    field :stats, as: :code, language: "json", hide_on: :index
    field :body_markdown, as: :textarea, hide_on: :index
    field :body_mjml, as: :code, language: "xml", hide_on: :index
    field :body_html, as: :code, language: "html", hide_on: :index
    field :created_at, as: :date_time, readonly: true, hide_on: :forms

    field :deliveries, as: :has_many
  end
end
