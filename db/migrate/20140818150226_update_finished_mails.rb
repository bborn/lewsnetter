class UpdateFinishedMails < ActiveRecord::Migration
  def change

    add_column :finished_mails, :subscription_id, :integer
    add_column :finished_mails, :mailing_list, :integer
    add_column :finished_mails, :campaign_id, :integer
    add_column :finished_mails, :opened_at, :datetime
    add_column :finished_mails, :clicked_at, :datetime
    add_column :finished_mails, :bounced_at, :datetime
    add_column :finished_mails, :bounces_count, :integer, :default => 0
    add_column :finished_mails, :delivered_at, :datetime
    add_column :finished_mails, :complaints_count, :integer, :default => 0
  end
end
