class Aaasm < ActiveRecord::Migration
  def change
    add_column :mail_campaigns, :aasm_state, :string
  end
end
