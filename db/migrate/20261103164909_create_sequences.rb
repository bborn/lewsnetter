# Automated, multi-step email flows (the Intercom "Series" replacement). A
# sequence enrolls a subscriber when a tracked event fires or when they enter
# a segment, then walks them through its steps on a delay.
class CreateSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :sequences do |t|
      t.references :team, null: false, foreign_key: true, type: :integer
      t.string :name, null: false

      # draft (not enrolling) / active (enrolling + sending) / paused (no new
      # enrollments, no sends; enrollments stay put and resume on re-activate).
      t.string :status, null: false, default: "draft"

      # event: enroll when Event#name == trigger_event_name is tracked.
      # segment: enroll when the subscriber matches trigger_segment (hourly sweep).
      t.string :trigger_type, null: false, default: "event"
      t.string :trigger_event_name
      t.references :trigger_segment, foreign_key: {to_table: :segments, on_delete: :nullify}, type: :integer

      # Matching the exit segment ends the enrollment before the next step.
      t.references :exit_segment, foreign_key: {to_table: :segments, on_delete: :nullify}, type: :integer

      # nil = a subscriber goes through the sequence once, ever. N = they may
      # re-enter N days after their previous enrollment started.
      t.integer :reentry_days

      t.references :sender_address, foreign_key: {on_delete: :nullify}, type: :integer

      t.timestamps
    end

    add_index :sequences, [:team_id, :status, :trigger_type]
  end
end
