class Template < ActiveRecord::Base
  validates_presence_of :html, :name
  has_many :campaigns

  rails_admin do
    field :html, :code_mirror
    field :name
  end


end
