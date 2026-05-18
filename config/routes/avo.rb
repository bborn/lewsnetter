# Avo admin panel. The engine is wrapped in a Devise `authenticate :user`
# route constraint — non-developers get a 404 from the router and never
# reach Avo's controllers. The gate is BulletTrain's `User#developer?`
# which reads the comma-separated `DEVELOPER_EMAILS` env var (same pattern
# also gates /sidekiq and the elevated CanCan abilities in
# app/models/ability.rb). Self-hosters override the env var on their own
# boxes.
if defined?(Avo::Engine)
  authenticate :user, lambda { |u| u.developer? } do
    mount Avo::Engine, at: Avo.configuration.root_path
  end

  # Custom tool routes injected INTO the engine so they live under
  # /admin/avo/* and inherit the authenticate-on-mount gate above. The
  # `home` action is wired as Avo's `config.home_path` so landing on
  # /admin/avo redirects here. See app/controllers/avo/tools_controller.rb.
  #
  # We use a plain Rails controller + view here (rather than Avo::Dashboard
  # + Avo::Cards::MetricCard) because dashboards/metric cards live in the
  # licensed avo-advanced add-on, not the OSS avo gem we depend on.
  Avo::Engine.routes.draw do
    get "home", to: "tools#home", as: :home
  end
end
