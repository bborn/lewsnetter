# URL helpers for cross-host links on the marketing surface
# (lewsnetter.dev → app.lewsnetter.dev). In production these always
# point at the app subdomain so signed-in flows land on the right
# canonical host. In dev they fall back to the same host the request
# came in on, so localhost links keep working.
module MarketingHelper
  APP_BASE_URL = "https://app.lewsnetter.dev".freeze

  def app_sign_in_url
    Rails.env.production? ? "#{APP_BASE_URL}/users/sign_in" : new_user_session_url
  end

  def app_sign_up_url
    Rails.env.production? ? "#{APP_BASE_URL}/users/sign_up" : new_user_registration_url
  end

  def app_dashboard_url
    Rails.env.production? ? "#{APP_BASE_URL}/account" : account_dashboard_url
  end
end
