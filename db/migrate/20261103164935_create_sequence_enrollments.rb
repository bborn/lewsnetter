class CreateSequenceEnrollments < ActiveRecord::Migration[8.1]
  def change
    create_table :sequence_enrollments do |t|
      t.references :sequence, null: false, foreign_key: true, type: :integer
      t.references :subscriber, null: false, foreign_key: true, type: :integer

      # 0-based index of the next step due.
      t.integer :current_step, null: false, default: 0
      t.datetime :next_send_at

      # active / completed / exited / suppressed
      t.string :state, null: false, default: "active"
      t.string :exit_reason
      t.integer :attempts, null: false, default: 0

      t.datetime :enrolled_at, null: false
      t.datetime :completed_at
      t.datetime :exited_at

      t.timestamps
    end

    # One live enrollment per subscriber per sequence; finished ones pile up
    # as history (re-entry).
    add_index :sequence_enrollments, [:sequence_id, :subscriber_id],
      unique: true, where: "state = 'active'",
      name: "index_sequence_enrollments_one_active"
    add_index :sequence_enrollments, [:state, :next_send_at]
  end
end
