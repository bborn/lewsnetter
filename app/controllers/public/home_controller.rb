class Public::HomeController < Public::ApplicationController
  # Public landing page at `/`. Logged-in users skip the marketing page +
  # land directly on their team dashboard so we don't make them re-navigate.
  def index
    if user_signed_in?
      redirect_to account_root_path
    else
      render :index
    end
  end

  # Allow your application to disable public sign-ups and be invitation only.
  include InviteOnlySupport

  # Make Bullet Train's documentation available at `/docs`.
  include DocumentationSupport
end
