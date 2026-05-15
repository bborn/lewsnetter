# frozen_string_literal: true

module Agent
  # Orchestrates a single user-message → assistant-response turn for an
  # AgentConversation. Persists each message + tool call. Streams events to
  # an optional `on_event` callable (the AgentChannel uses this).
  #
  # Event payloads (passed to on_event.call(event_hash)):
  #   {type: :user_message,   message_id:, content:}
  #   {type: :tool_call,      message_id:, tool_name:, arguments:}
  #   {type: :tool_result,    message_id:, tool_name:, result:}
  #   {type: :assistant_message, message_id:, content:}
  #   {type: :error,          message:}
  class Runner
    NOT_CONFIGURED_MESSAGE = <<~MSG.strip
      LLM not configured. Set up your key in `credentials.llm.api_key`
      (or `ANTHROPIC_API_KEY`) and restart, then try again. The MCP tools still work via
      direct API calls — the chat experience is what's blocked.
    MSG

    def initialize(conversation:, on_event: nil)
      @conversation = conversation
      @on_event = on_event
      @context = Mcp::Tool::Context.new(user: conversation.user, team: conversation.team)
    end

    def handle_user_message(content)
      user_msg = @conversation.agent_messages.create!(role: "user", content: content)
      emit_message(user_msg)

      unless ::Llm::Configuration.current.usable?
        return persist_assistant(NOT_CONFIGURED_MESSAGE)
      end

      respond_via_llm(content)
    rescue => e
      Rails.logger.error("[agent] runner failed: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      err_msg = @conversation.agent_messages.create!(role: "error", error_class: e.class.name, error_message: e.message)
      emit_message(err_msg)
    end

    private

    def respond_via_llm(content)
      if AI::Base.force_stub
        return persist_assistant("(stub agent reply — AI::Base.force_stub is set; #{Mcp::Tool::Loader.load_all.size} tools available)")
      end

      tools = ToolAdapter.adapt_all(context: @context)
      chat = RubyLLM.chat(model: ::Llm::Configuration.current.default_model)
      chat = chat.with_tools(*tools) if tools.any?
      chat = chat.with_instructions(system_prompt)

      result = chat.ask(content)
      assistant_text = result.respond_to?(:content) ? result.content : result.to_s
      persist_assistant(assistant_text.to_s)
    end

    def replay_history(chat)
      # Intentionally a no-op for v1. Each turn is stateless — multi-turn
      # memory (replaying prior messages) is a separate design iteration.
      # ruby_llm's exact API for prepending history (add_message?) hasn't
      # been pinned yet.
    end

    def system_prompt
      <<~PROMPT
        You are an in-app assistant for Lewsnetter, an AI-native email marketing tool.
        You're helping #{@context.user.email} on team "#{@context.team.name}".

        You have tools that mirror the full Lewsnetter API: list/get/create/update subscribers,
        segments, email templates, campaigns, sender addresses; send tests; trigger sends; etc.
        Plus three LLM tools that wrap the existing AI services (draft a campaign, translate
        a question into a segment, analyze a sent campaign).

        Use tools when the user asks for an action. Don't fabricate data — if you don't have
        it, look it up via a tool first. Be terse; users prefer short replies. When you take
        a destructive action (send, delete), confirm intent first if the user hasn't been
        explicit.
      PROMPT
    end

    def persist_assistant(text)
      msg = @conversation.agent_messages.create!(role: "assistant", content: text)
      emit_message(msg)
      msg
    end

    # Broadcast a single AgentMessage to the channel. Includes the rendered
    # HTML so the Stimulus controller appends a styled bubble that matches
    # the page-load render of `_message.html.erb`. Without `html`, the JS
    # would have to duplicate the partial's Tailwind classes inline.
    def emit_message(message)
      payload = {
        type: "#{message.role}_message",
        message_id: message.id,
        role: message.role,
        content: message.content,
        html: render_message_html(message)
      }
      @on_event&.call(payload)
    end

    def render_message_html(message)
      ApplicationController.render(
        partial: "account/agent_conversations/message",
        locals: {message: message}
      )
    rescue => e
      Rails.logger.warn("[agent] failed to render message partial: #{e.class}: #{e.message}")
      nil
    end
  end
end
