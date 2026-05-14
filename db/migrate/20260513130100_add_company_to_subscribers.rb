class AddCompanyToSubscribers < ActiveRecord::Migration[8.1]
  def change
    add_reference :subscribers, :company, foreign_key: true, null: true, index: true
  end
end
