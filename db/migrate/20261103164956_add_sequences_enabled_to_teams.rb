# Per-team feature flag for Sequences. Off by default; flip with
# `team.update!(sequences_enabled: true)` (console or Avo).
class AddSequencesEnabledToTeams < ActiveRecord::Migration[8.1]
  def change
    add_column :teams, :sequences_enabled, :boolean, null: false, default: false
  end
end
