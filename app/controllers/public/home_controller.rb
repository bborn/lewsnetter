class Public::HomeController < Public::ApplicationController
  # Public landing page at `/`. Two surfaces:
  #
  #   - lewsnetter.dev/ — marketing landing (this view)
  #   - app.lewsnetter.dev/ — bounce signed-in users to the dashboard;
  #     bounce signed-out users to the marketing apex.
  def index
    if user_signed_in?
      # Signed in? Send to dashboard on the app subdomain (or current host
      # if we're already on the app surface, e.g. local dev).
      redirect_to dashboard_url_for(request)
    elsif on_app_subdomain?(request)
      # Anonymous visitor hit app.lewsnetter.dev/ — bounce them to the
      # marketing apex so the landing renders there.
      redirect_to marketing_root_url(request), status: :moved_permanently
    else
      render :index
    end
  end

  # Allow your application to disable public sign-ups and be invitation only.
  include InviteOnlySupport

  # Make Bullet Train's documentation available at `/docs`.
  include DocumentationSupport

  private

  def on_app_subdomain?(request)
    request.host.start_with?("app.")
  end

  def dashboard_url_for(request)
    if Rails.env.production? && !on_app_subdomain?(request)
      "https://app.lewsnetter.dev/account"
    else
      account_dashboard_url
    end
  end

  def marketing_root_url(request)
    Rails.env.production? ? "https://lewsnetter.dev/" : root_url
  end
end
