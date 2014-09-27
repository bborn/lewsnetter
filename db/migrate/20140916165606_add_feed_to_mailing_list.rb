class AddFeedToMailingList < ActiveRecord::Migration
  def change
    add_column :mailing_lists, :feed, :string
  end
end
