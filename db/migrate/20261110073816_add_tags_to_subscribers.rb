class AddTagsToSubscribers < ActiveRecord::Migration[8.1]
  # Own column, not custom_attributes: the source-app sync replaces
  # custom_attributes wholesale, which would wipe tags set by sequences.
  def change
    add_column :subscribers, :tags, :json, default: [], null: false
  end
end
