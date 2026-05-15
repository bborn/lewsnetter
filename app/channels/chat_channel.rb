# frozen_string_literal: true

# ActionCable channel for the in-app agent chat. Subscribes to a single Chat;
# messages perform `send_message` actions.
#
# Lifecycle per send_message:
#   1. Add user message to chat (persisted by acts_as_chat).
#   2. Broadcast it.
#   3. Configure tools (per-context MCP adapter).
#   4. Configure on_new_message / on_end_message callbacks to broadcast each
#      assistant message + tool result as it arrives.
#   5. chat.complete — runs the model loop. ruby_llm handles memory by
#      replaying the chat's persisted messages on every turn.
class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat = Chat.find_by(id: params[:chat_id])
    if chat.nil? || chat.user_id != current_user.id
      reject
      return
    end

    @chat = chat
    stream_for chat
  end

  def send_message(data)
    return if @chat.nil?

    content = data["content"].to_s
    return if content.blank?

    unless ::Llm::Configuration.current.usable?
      user_msg = @chat.messages.create!(role: "user", content: content)
      broadcast_message(user_msg)
      not_configured = @chat.messages.create!(
        role: "assistant",
        content: "LLM not configured. Set credentials.llm.api_key (or ANTHROPIC_API_KEY) and restart."
      )
      broadcast_message(not_configured)
      return
    end

    run_chat_turn(content)
  rescue => e
    Rails.logger.error("[chat] turn failed: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    err = @chat.messages.create!(
      role: "assistant",
      content: "Sorry — that turn errored: #{e.class}: #{e.message}"
    )
    broadcast_message(err)
  end

  private

  def run_chat_turn(content)
    ctx = Mcp::Tool::Context.new(user: @chat.user, team: @chat.team)
    tools = Chats::ToolAdapter.adapt_all(context: ctx)

    @chat.with_instructions(system_prompt(ctx), append: false)
    @chat.with_tools(*tools) if tools.any?

    # Broadcast each persisted message as it lands. ruby_llm fires this
    # callback after the assistant/tool message has been saved, so we just
    # need to fetch by id and push it.
    seen_ids = @chat.messages.pluck(:id).to_set
    @chat.on_end_message do |_msg|
      @chat.messages.where("id NOT IN (?)", seen_ids).order(:id).each do |record|
        broadcast_message(record)
        seen_ids << record.id
      end
    end

    # ask() adds the user message + runs the tool loop until the model stops.
    # ruby_llm replays the persisted history automatically (acts_as_chat).
    @chat.ask(content)
  end

  def broadcast_message(message)
    ChatChannel.broadcast_to(@chat, {
      type: "message",
      role: message.role,
      content: message.content,
      message_id: message.id,
      html: render_message_html(message)
    })
  end

  def render_message_html(message)
    ApplicationController.render(
      partial: "account/chats/message",
      locals: {message: message}
    )
  rescue => e
    Rails.logger.warn("[chat] failed to render message partial: #{e.class}: #{e.message}")
    nil
  end

  def system_prompt(ctx)
    <<~PROMPT
      You are an in-app assistant for Lewsnetter, an AI-native email marketing tool.
      You're helping #{ctx.user.email} on team "#{ctx.team.name}".

      You have tools that mirror the full Lewsnetter API: list/get/create/update
      subscribers, segments, email templates, campaigns, sender addresses;
      send tests; trigger sends; etc. Plus three LLM tools that wrap the existing
      AI services (draft a campaign, translate a question into a segment,
      analyze a sent campaign).

      Use tools when the user asks for an action. Don't fabricate data — if you
      don't have it, look it up via a tool first. Be terse; users prefer short
      replies. When you take a destructive action (send, delete), confirm intent
      first if the user hasn't been explicit.
    PROMPT
  end
end
