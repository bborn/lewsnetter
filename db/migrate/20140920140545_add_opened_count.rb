class AddOpenedCount < ActiveRecord::Migration
  def change
    add_column :finished_mails, :opens_count, :integer, :default => 0
  end
end
