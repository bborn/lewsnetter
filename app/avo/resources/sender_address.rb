class Avo::Resources::SenderAddress < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :email, as: :text
    field :name, as: :text
    field :verified, as: :boolean
    field :ses_status, as: :text
  end
end
