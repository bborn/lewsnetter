module ApplicationHelper
  include Helpers::Base

  def current_theme
    :light
  end

  # Renders a "→ Open in agent" button that creates a new AgentConversation
  # pre-seeded with the given prompt. Only renders when the user is signed in
  # and a current_team is available.
  #
  # Example:
  #   <%= open_in_agent_link("Draft a newsletter about: #{@brief}", label: "→ Open in agent") %>
  def open_in_agent_link(prompt, label: "→ Open in agent", html_options: {})
    return unless user_signed_in? && current_team
    button_to(
      label,
      account_team_agent_conversations_path(current_team),
      method: :post,
      params: {agent_conversation: {}, starter_prompt: prompt},
      class: html_options[:class] || "card-action",
      data: html_options[:data] || {turbo: false}
    )
  end
end
