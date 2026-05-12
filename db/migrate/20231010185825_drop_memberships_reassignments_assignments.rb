class DropMembershipsReassignmentsAssignments < ActiveRecord::Migration[7.0]
  def change
    drop_table :memberships_reassignments_assignments
    # The table created by the earlier `Create...TangibleThingsReassignments`
    # migration uses its full name on SQLite. On Postgres the identifier got
    # silently truncated to 63 chars (`...tangi`), which is the name this
    # migration used to drop. On SQLite there is no identifier-length cap,
    # so we drop the full table name and fall back to the truncated form
    # for installs that may have been migrated through Postgres at some
    # point in the past.
    full = :memberships_reassignments_scaffolding_completely_concrete_tangible_things_reassignments
    truncated = :memberships_reassignments_scaffolding_completely_concrete_tangi

    if table_exists?(full)
      drop_table full
    elsif table_exists?(truncated)
      drop_table truncated
    end
  end
end
