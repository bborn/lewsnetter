# Public legal pages — Privacy, Terms, DPA, Acceptable Use. Mounted at
# top-level routes (/privacy, /terms, etc.) so they're linkable from the
# landing page footer + reachable without authentication.
#
# These are static-content pages but rendered through Rails (instead of
# pre-built HTML) so we can interpolate the canonical hostname, contact
# email, last-updated date, and any future per-environment values without
# regenerating files.
class LegalController < Public::ApplicationController
  LAST_UPDATED = "May 16, 2026".freeze

  def privacy
    render_legal_page
  end

  def terms
    render_legal_page
  end

  def dpa
    render_legal_page
  end

  def acceptable_use
    render_legal_page
  end

  private

  def render_legal_page
    @last_updated = LAST_UPDATED
    @contact_email = ENV.fetch("LEWSNETTER_LEGAL_EMAIL", "legal@lewsnetter.com")
    @abuse_email   = ENV.fetch("LEWSNETTER_ABUSE_EMAIL", "abuse@lewsnetter.com")
    @company_name  = ENV.fetch("LEWSNETTER_COMPANY", "Lewsnetter")
  end
end
