# frozen_string_literal: true

# ActionCable channel for the in-app agent chat.
#
# Subscribe with chat_id; client `perform("send_message", {content})` runs a
# turn. ruby_llm handles memory, the tool loop, and persistence — we just
# wire its callbacks into broadcasts so the UI updates live.
#
# Event payloads (all carry `type` and `chat_id`):
#   {type: "message_start",  message_id, role}                        — empty bubble appears
#   {type: "chunk",          message_id, content_delta}               — append text to bubble
#   {type: "message_end",    message_id, html}                        — replace bubble with final rendered HTML (markdown formatted)
#   {type: "tool_call",      tool_call_id, name, arguments}           — "→ Calling foo({...})"
#   {type: "tool_result",    tool_call_id, name, result_excerpt}      — "← result"
#   {type: "error",          html}                                    — turn-level failure
class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat = Chat.find_by(id: params[:chat_id])
    unless authorized?(chat)
      reject
      return
    end

    @chat = chat
    stream_for chat
  end

  def send_message(data)
    return if @chat.nil?

    # A subscription lives as long as the socket, so the check in
    # #subscribed goes stale once the user leaves the team.
    unless authorized?(@chat)
      stop_all_streams
      return
    end

    content = data["content"].to_s
    return if content.blank?

    unless ::Llm::Configuration.current.usable?
      user_msg = @chat.messages.create!(role: "user", content: content)
      broadcast_full_message(user_msg)
      not_configured = @chat.messages.create!(
        role: "assistant",
        content: "LLM not configured. Set credentials.llm.api_key (or ANTHROPIC_API_KEY) and restart."
      )
      broadcast_full_message(not_configured)
      return
    end

    run_chat_turn(content)
  rescue => e
    Rails.logger.error("[chat] turn failed: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    err = @chat.messages.create!(
      role: "assistant",
      content: "Sorry, that turn errored."
    )
    broadcast_full_message(err)
  end

  private

  # The rule Ability grants Chat by (`team_id: user.team_ids, user_id:
  # user.id`), read fresh each time. Tools run against chat.team, so the
  # owner must still belong to that team on every turn.
  def authorized?(chat)
    chat.present? &&
      chat.user_id == current_user.id &&
      Membership.exists?(team_id: chat.team_id, user_id: current_user.id)
  end

  def run_chat_turn(content)
    ctx = Mcp::Tool::Context.new(user: @chat.user, team: @chat.team)
    tools = Chats::ToolAdapter.adapt_all(context: ctx)

    @chat.with_instructions(system_prompt(ctx))
    @chat.with_tools(*tools) if tools.any?

    @streamed_message_id = nil
    @user_message_broadcast = false
    register_broadcast_callbacks

    # Block form: chunk-by-chunk streaming. Each chunk has .content (text
    # delta). The first chunk starts a streaming bubble; subsequent chunks
    # append. after_message replaces it with the final rendered HTML.
    @chat.ask(content) do |chunk|
      next unless chunk&.content&.present?
      if @streamed_message_id.nil?
        # The placeholder assistant message ruby_llm created for this reply.
        @streamed_message_id = @chat.messages.order(:id).last&.id
        broadcast(type: "message_start", message_id: @streamed_message_id, role: "assistant")
      end
      broadcast(
        type: "chunk",
        message_id: @streamed_message_id,
        content_delta: chunk.content.to_s
      )
    end
  end

  # Wire ruby_llm callbacks to ActionCable broadcasts. The before_/after_
  # callbacks add to the list instead of replacing, and the chat record
  # keeps its RubyLLM::Chat for the life of this subscription, so register
  # them once; per-turn state lives in instance variables reset each turn.
  #
  # before_message fires when an assistant reply starts (the user message is
  # already saved). after_message fires once ruby_llm has saved a finished
  # assistant or tool message. before_tool_call/after_tool_result bracket
  # each tool invocation.
  def register_broadcast_callbacks
    return if @broadcast_callbacks_registered
    @broadcast_callbacks_registered = true

    @chat.before_message do
      # Broadcast the user message before the assistant placeholder.
      unless @user_message_broadcast
        user_msg = @chat.messages.where(role: "user").order(:id).last
        broadcast_full_message(user_msg) if user_msg
        @user_message_broadcast = true
      end
    end

    @chat.after_message do |_msg|
      record = @chat.messages.order(:id).last
      next if record.nil?

      # Skip messages already represented by live events to avoid duplicate
      # renders in the chat panel:
      # - assistant placeholders (empty content, only tool_calls): the live
      #   tool_call event already drew the "→ name(args)" line
      # - tool result messages: the live tool_result event drew "← result"
      role = record.role.to_s
      next if role == "tool"
      next if role == "assistant" && record.content.to_s.strip.empty?

      broadcast(type: "message_end", message_id: record.id, html: render_message_html(record))
      @streamed_message_id = nil
    end

    @chat.before_tool_call do |tool_call|
      broadcast(
        type: "tool_call",
        tool_call_id: tool_call.id,
        name: tool_call.name,
        arguments: tool_call.arguments
      )
    end

    @chat.after_tool_result do |result|
      # ruby_llm yields the raw tool return value (string/hash). Format
      # compactly for the UI; the full result is in the saved Message
      # (role: "tool").
      excerpt = result.is_a?(String) ? result : result.to_json
      broadcast(
        type: "tool_result",
        result_excerpt: excerpt.to_s.truncate(200)
      )
    end
  end

  def broadcast_full_message(message)
    broadcast(
      type: "message_full",
      message_id: message.id,
      role: message.role,
      html: render_message_html(message)
    )
  end

  def broadcast(payload)
    ChatChannel.broadcast_to(@chat, payload.merge(chat_id: @chat.id))
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
