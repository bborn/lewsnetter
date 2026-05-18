# URL helpers for cross-host links on the marketing surface
# (e.g. lewsnetter.dev → app.lewsnetter.dev for the hosted version).
# Self-hosters who run a single-host deployment don't set APP_BASE_URL
# and these fall back to same-host route helpers.
module MarketingHelper
  # `APP_BASE_URL` is the canonical app host. Hosted Lewsnetter sets this
  # to "https://app.lewsnetter.dev"; self-hosters typically leave it
  # unset so all routes resolve same-host.
  def app_base_url
    ENV["APP_BASE_URL"].presence
  end

  def app_sign_in_url
    app_base_url ? "#{app_base_url}/users/sign_in" : new_user_session_url
  end

  def app_sign_up_url
    app_base_url ? "#{app_base_url}/users/sign_up" : new_user_registration_url
  end

  def app_dashboard_url
    app_base_url ? "#{app_base_url}/account" : account_dashboard_url
  end
end
