module ApplicationHelper
  include Helpers::Base

  def current_theme
    :light
  end

  # The DNS CNAME target a tenant points their branded unsubscribe/tracking
  # subdomain at. Hosted Lewsnetter sets BRANDED_HOST_CNAME_TARGET to a
  # DNS-only (grey-cloud) host resolving straight to the origin — Cloudflare
  # error 1014 forbids a cross-account CNAME onto a proxied record, so the
  # target must not be a Cloudflare-proxied host. Self-hosters running a
  # single host can leave it unset: it then falls back to the app's own
  # host, which a tenant can CNAME to directly.
  def branded_host_cname_target
    ENV["BRANDED_HOST_CNAME_TARGET"].presence ||
      (ENV["BASE_URL"].present? ? URI(ENV["BASE_URL"]).host : request.host)
  end

  # Renders a "→ Open in agent" button that creates a new Chat pre-seeded
  # with the given prompt. Only renders when the user is signed in and a
  # current_team is available.
  #
  # Example:
  #   <%= open_in_agent_link("Draft a newsletter about: #{@brief}", label: "→ Open in agent") %>
  def open_in_agent_link(prompt, label: "→ Open in agent", html_options: {})
    return unless user_signed_in? && current_team
    button_to(
      label,
      account_team_chats_path(current_team),
      method: :post,
      params: {chat: {}, starter_prompt: prompt},
      class: html_options[:class] || "card-action",
      data: html_options[:data] || {turbo: false}
    )
  end
end
