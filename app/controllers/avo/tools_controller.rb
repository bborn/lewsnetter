# Avo custom tools. Inherits from Avo::ApplicationController so it picks up
# Avo's chrome (sidebar, breadcrumbs, devise helpers) — no extra auth setup
# needed beyond the `authenticate :user, ->(u) { u.developer? }` mount
# constraint in config/routes/avo.rb.
#
# Add a new tool by:
#   1. Adding an action here.
#   2. Adding a route under config/routes/avo.rb inside the
#      `Avo::Engine.routes.draw` block.
#   3. Adding a view at app/views/avo/tools/<action>.html.erb.
class Avo::ToolsController < Avo::ApplicationController
  # Operator home dashboard. Computes the small set of counters + recent
  # signups that we want to see whenever we land at /admin/avo. Kept in
  # the controller (rather than a service object) because it's a tiny,
  # admin-only read with no reuse outside this view.
  def home
    @page_title = "Lewsnetter operator dashboard"
    add_breadcrumb "Home"

    # Signups over time. Use straightforward Time.current - N.days windows
    # so the chart reads as "last 24h / last 7d / last 30d" rather than
    # calendar weeks/months — easier to reason about for a tiny org.
    now = Time.current
    @signups_24h = User.where(created_at: (now - 24.hours)..).count
    @signups_7d = User.where(created_at: (now - 7.days)..).count
    @signups_30d = User.where(created_at: (now - 30.days)..).count

    # Per-entity counters. Spans all teams — this is the operator view of
    # the whole platform, not a team-scoped view.
    @counts = {
      users: User.count,
      teams: Team.count,
      subscribers: Subscriber.count,
      subscribed_subscribers: Subscriber.where(subscribed: true).count,
      companies: Company.count,
      segments: Segment.count,
      email_templates: EmailTemplate.count,
      campaigns: Campaign.count,
      campaigns_sent: Campaign.where(status: "sent").count,
      deliveries: Delivery.count,
      suppressions: Suppression.count,
      ses_configurations: ::Team::SesConfiguration.count,
      verified_ses_configurations: ::Team::SesConfiguration.verified.count,
      ses_domains: ::Team::SesDomain.count,
      verified_ses_domains: ::Team::SesDomain.verified.count
    }

    # Recent signups table. Cap at 25 so the panel stays scannable; the
    # full list lives under the Users resource.
    @recent_users = User.includes(:current_team).order(created_at: :desc).limit(25)
  end
end
