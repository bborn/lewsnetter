class AddLastClickedUrlToDeliveries < ActiveRecord::Migration[8.1]
  # Phase 2 (open + click tracking). We capture the most-recently-clicked URL
  # per delivery so the postmortem + future per-link analytics have a real
  # value to display without joining a separate clicks table. If/when we want
  # per-click history we'll add a `delivery_clicks` table; for now the
  # aggregated last value is enough for the campaign show stats panel.
  def change
    add_column :deliveries, :last_clicked_url, :text
  end
end
