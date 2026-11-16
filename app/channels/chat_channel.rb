# frozen_string_literal: true

# ActionCable channel for the in-app agent chat.
#
# Subscribe with chat_id; client `perform("send_message", {content})` runs a
# turn. ruby_llm handles memory, the tool loop, and persistence — we just
# wire its callbacks into broadcasts so the UI updates live.
#
# A call to a tool that declares requires_approval pauses the turn. The
# panel shows it with Approve and Decline, which `perform("approve" |
# "decline", {tool_call_id})` answer; the turn then carries on. The
# decision lives on the tool call row, so a reload still shows the call.
#
# Event payloads (all carry `type` and `chat_id`):
#   {type: "message_start",  message_id, role}                        — empty bubble appears
#   {type: "chunk",          message_id, content_delta}               — append text to bubble
#   {type: "message_end",    message_id, html}                        — replace bubble with final rendered HTML (markdown formatted)
#   {type: "tool_call",      tool_call_id, name, arguments}           — "→ Calling foo({...})"
#   {type: "tool_result",    tool_call_id, name, result_excerpt}      — "← result"
#   {type: "approval_request",  tool_call_id, html}                   — Approve/Decline card
#   {type: "approval_decided",  tool_call_id, approved}               — the card's buttons go
#   {type: "error",          html}                                    — turn-level failure
class ChatChannel < ApplicationCable::Channel
  # What the model gets in place of a declined call's result.
  DECLINED_NOTE = "The user declined this call, so it did not run."
  MOVED_ON_NOTE = "The user sent a new message instead of approving this call, so it did not run."

  # The stream a chat broadcasts on: "chat:<GlobalID>". Don't hand the chat
  # itself to stream_for/broadcast_to. ruby_llm 2 makes acts_as_chat records
  # Enumerable over their messages, and ActionCable's broadcasting_for calls
  # Array(model), so the name would be built from the chat's messages and
  # change with every message saved.
  def self.stream_key(chat)
    chat.to_gid_param
  end

  def subscribed
    chat = Chat.find_by(id: params[:chat_id])
    unless authorized?(chat)
      reject
      return
    end

    @chat = chat
    stream_for self.class.stream_key(chat)
  end

  def send_message(data)
    return unless still_authorized?

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

    run_turn(new_message: true) do |on_chunk|
      # ruby_llm takes no new message while a call waits for an answer, so
      # treat the message as the user moving on.
      decline_pending_approvals(MOVED_ON_NOTE)
      @chat.ask(content, &on_chunk)
    end
  rescue => e
    turn_failed(e)
  end

  def approve(data)
    # answer, not approve: approve records over a decision another tab made
    # since we read the call as pending; answer lets the first one stand.
    decide(data, approved: true) { |question| @chat.answer(question) }
  end

  def decline(data)
    decide(data, approved: false) { |question| @chat.decline(question, DECLINED_NOTE) }
  end

  private

  # A subscription lives as long as the socket, so the check in
  # #subscribed goes stale once the user leaves the team.
  def still_authorized?
    return false if @chat.nil?
    return true if authorized?(@chat)

    stop_all_streams
    false
  end

  # Records the user's answer to one pending call and carries the turn on.
  # The tool's ability is checked again when the call runs (Base#invoke).
  def decide(data, approved:)
    return unless still_authorized?

    question = pending_approvals.find { |q| q.id == data["tool_call_id"].to_s }
    # Already answered, e.g. by a second click or in another tab.
    return if question.nil?

    yield question
    broadcast(type: "approval_decided", tool_call_id: question.id, approved: approved)
    run_turn(new_message: false) { |on_chunk| @chat.complete(&on_chunk) }
  rescue => e
    turn_failed(e)
  end

  def turn_failed(error)
    Rails.logger.error("[chat] turn failed: #{error.class}: #{error.message}\n#{Array(error.backtrace).first(8).join("\n")}")
    err = @chat.messages.create!(
      role: "assistant",
      content: "Sorry, that turn errored."
    )
    broadcast_full_message(err)
  end

  # The rule Ability grants Chat by (`team_id: user.team_ids, user_id:
  # user.id`), read fresh each time. Tools run against chat.team, so the
  # owner must still belong to that team on every turn.
  def authorized?(chat)
    chat.present? &&
      chat.user_id == current_user.id &&
      Membership.exists?(team_id: chat.team_id, user_id: current_user.id)
  end

  # Sets the chat up for a turn, yields the chunk handler to the block that
  # runs it (ask or complete), then shows any call left waiting for the
  # user. `new_message` is false when an approval resumes the turn, so the
  # last user message isn't broadcast twice.
  def run_turn(new_message:)
    ctx = tool_context
    tools = Chats::ToolAdapter.adapt_all(context: ctx)

    @chat.with_instructions(system_prompt(ctx))
    @chat.with_tools(*tools) if tools.any?

    @streamed_message_id = nil
    @user_message_broadcast = !new_message
    register_broadcast_callbacks

    yield method(:broadcast_chunk)

    pending_approvals.each do |question|
      broadcast(type: "approval_request", tool_call_id: question.id, html: render_approval_html(question))
    end
  end

  # Chunk-by-chunk streaming. Each chunk has .content (text delta). The
  # first chunk starts a streaming bubble; subsequent chunks append.
  # after_message replaces it with the final rendered HTML.
  def broadcast_chunk(chunk)
    return unless chunk&.content.present?

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

  def pending_approvals
    @chat.pending_questions.select(&:approval?)
  end

  # Declines every pending call with `note`, and runs the tool round so
  # each declined call gets its refusal as its result.
  def decline_pending_approvals(note)
    pending = pending_approvals
    return if pending.empty?

    pending.each do |question|
      @chat.decline(question, note)
      broadcast(type: "approval_decided", tool_call_id: question.id, approved: false)
    end
    @chat.run_tools
  end

  def tool_context
    Mcp::Tool::Context.new(user: @chat.user, team: @chat.team)
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
    ChatChannel.broadcast_to(self.class.stream_key(@chat), payload.merge(chat_id: @chat.id))
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

  def render_approval_html(question)
    ApplicationController.render(
      partial: "account/chats/approval",
      locals: {question: question, chat: @chat}
    )
  end

  def system_prompt(ctx)
    <<~PROMPT
      You are an in-app assistant for Lewsnetter, an AI-native email marketing tool.
      You're helping #{ctx.user.email} on team "#{ctx.team.name}".

      You have tools that mirror the full Lewsnetter API: list/get/create/update
      subscribers, segments, email templates, campaigns, sender addresses;
      send tests; etc. Plus two LLM tools that wrap the existing
      AI services (draft a campaign, analyze a sent campaign).

      Use tools when the user asks for an action. Don't fabricate data — if you
      don't have it, look it up via a tool first. Be terse; users prefer short
      replies. When you take a destructive action (delete), confirm intent first
      if the user hasn't been explicit. Deletes, turning Sequences on or off and
      activating a sequence wait for the user to press Approve in this chat;
      if they decline, don't try the call again unless they ask. You can't send
      or schedule campaigns: when one is ready, tell the user to use the Send
      button on its page.
    PROMPT
  end
end
