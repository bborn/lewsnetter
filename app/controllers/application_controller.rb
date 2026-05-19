class ApplicationController < ActionController::Base
  include Controllers::Base

  protect_from_forgery with: :exception, prepend: true

  # PaperTrail: stamp every write with `current_user.id` as whodunnit. The
  # `versions` table stores it as a string; the History UI resolves it back
  # via `User.find_by(id: whodunnit)&.email`. Devise hasn't always populated
  # `current_user` by the time non-Account controllers fire (webhooks,
  # tracking pixels, etc.), so we guard with `respond_to?` rather than
  # assuming a signed-in user is present.
  before_action :set_paper_trail_whodunnit

  def user_for_paper_trail
    return nil unless respond_to?(:current_user)
    current_user&.id&.to_s
  end
end
