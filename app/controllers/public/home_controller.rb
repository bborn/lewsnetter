class Public::HomeController < Public::ApplicationController
  # Public landing page at `/`. Two surfaces:
  #
  #   - lewsnetter.dev/ — marketing landing (this view)
  #   - app.lewsnetter.dev/ — bounce signed-in users to the dashboard;
  #     bounce signed-out users to the marketing apex when configured.
  def index
    marketing_base = ENV["MARKETING_BASE_URL"].presence

    if user_signed_in?
      # Signed in? Send to dashboard on the app subdomain (or current host
      # in dev). Cross-host redirects need allow_other_host since Rails 7.
      redirect_to dashboard_url_for(request), allow_other_host: true
    elsif on_app_subdomain?(request) && separate_marketing_host?(marketing_base)
      # Anonymous visitor hit app.lewsnetter.dev/ — bounce to marketing apex
      # so the landing renders at its canonical host.
      redirect_to "#{marketing_base.chomp("/")}/",
        status: :moved_permanently, allow_other_host: true
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
    app_base = ENV["APP_BASE_URL"].presence
    if app_base && !on_app_subdomain?(request)
      "#{app_base.chomp("/")}/account"
    else
      account_dashboard_url
    end
  end

  def separate_marketing_host?(marketing_base)
    host = URI.parse(marketing_base).host if marketing_base
    host.present? && !host.casecmp?(request.host)
  end
end
