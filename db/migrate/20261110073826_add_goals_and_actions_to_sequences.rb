class AddGoalsAndActionsToSequences < ActiveRecord::Migration[8.1]
  def change
    change_table :sequences do |t|
      t.references :goal_segment, foreign_key: false
      t.string :goal_event_name
      t.json :excluded_sequence_ids, default: [], null: false
      t.integer :finish_after_minutes, default: 0, null: false
      t.string :completed_tag
    end

    change_table :sequence_steps do |t|
      t.string :action_trigger
      t.string :action_tag
      t.boolean :action_exit, default: false, null: false
      t.string :sent_tag
    end

    change_table :sequence_enrollments do |t|
      t.integer :pending_action_step
      t.datetime :pending_action_since
    end
  end
end
