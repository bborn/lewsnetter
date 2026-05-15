# In-App Agent Implementation Plan (Phase 5 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A conversational chat panel built into the Lewsnetter UI that uses the same MCP tool registry to perform actions on behalf of the user. Backed by `ruby_llm`, streamed via ActionCable, persisted as `AgentConversation` + `AgentMessage`. Replaces the bespoke AI panels (drafter, segment translator, postmortem) — those still work, but the agent panel can do the same things plus chain across them.

**Architecture:** The agent's tools are the same `Mcp::Tool::Base` descendants registered with the MCP server — but invoked in-process (no HTTP roundtrip). `Agent::ToolAdapter` bridges our `Mcp::Tool::Base` DSL into `ruby_llm`'s tool format. `Agent::Runner` runs the turn loop and emits events to `AgentChannel`. The UI is a right-side collapsible panel in the `account` layout, controlled by a Stimulus controller. No new auth — the panel uses the existing Devise session (no Doorkeeper token needed for in-app use).

**Tech Stack:** Rails 8.1 + ActionCable, `ruby_llm 1.15` with tool-use, Stimulus, the existing tool registry from Phases 1-2, the existing `Llm::Configuration` from Phase 4.

**Reference spec:** `docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md` §"In-app agent"

**Out of scope:** Cross-linking existing AI panels (Phase 6).

**Note on the "Agents SDK":** The user's brief mentioned using the "Anthropic agents SDK." That SDK is Python-first; there's no Ruby equivalent. We use `ruby_llm` (already in the app, supports tool use, and has the Anthropic provider) instead. Functionally equivalent for our purpose: model-driven tool-use loops.

---

## File structure

**Created:**
- `db/migrate/<timestamp>_create_agent_conversations_and_messages.rb`
- `app/models/agent_conversation.rb`
- `app/models/agent_message.rb`
- `app/services/agent/tool_adapter.rb`
- `app/services/agent/runner.rb`
- `app/channels/agent_channel.rb`
- `app/controllers/account/agent_conversations_controller.rb`
- `app/controllers/account/agent_messages_controller.rb`
- `app/views/account/agent_conversations/_panel.html.erb` (the right-side panel)
- `app/views/account/agent_conversations/_message.html.erb` (single message bubble)
- `app/javascript/controllers/agent_chat_controller.js`
- Tests for each
- `app/views/themes/light/layouts/_account.html.erb` — modified to include the panel partial

**Modified:**
- `config/routes.rb` — add agent routes under `/account/`

---

## Task 1: Migration + models (`AgentConversation`, `AgentMessage`)

**Files:**
- Create: `db/migrate/<timestamp>_create_agent_conversations_and_messages.rb`
- Create: `app/models/agent_conversation.rb`
- Create: `app/models/agent_message.rb`
- Create: `test/models/agent_conversation_test.rb`
- Create: `test/models/agent_message_test.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails g migration CreateAgentConversationsAndMessages
```

Then edit the migration:

```ruby
# db/migrate/<timestamp>_create_agent_conversations_and_messages.rb
class CreateAgentConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_conversations do |t|
      t.references :team, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :title, null: true   # optional human label, derived later
      t.timestamps
    end
    add_index :agent_conversations, [:team_id, :user_id]

    create_table :agent_messages do |t|
      t.references :agent_conversation, null: false, foreign_key: true, index: true
      t.string :role, null: false   # user | assistant | tool_call | tool_result | error
      t.text :content                # the markdown body for user/assistant messages
      t.string :tool_name            # for role=tool_call|tool_result
      t.json :tool_arguments         # for role=tool_call
      t.json :tool_result            # for role=tool_result
      t.string :error_class          # for role=error
      t.text :error_message          # for role=error
      t.timestamps
    end
    add_index :agent_messages, [:agent_conversation_id, :created_at]
  end
end
```

- [ ] **Step 2: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Implement models**

```ruby
# app/models/agent_conversation.rb
class AgentConversation < ApplicationRecord
  belongs_to :team
  belongs_to :user
  has_many :agent_messages, -> { order(:created_at) }, dependent: :destroy

  validates :team_id, presence: true
  validates :user_id, presence: true

  def message_count
    agent_messages.size
  end

  def derived_title
    title.presence || agent_messages.where(role: "user").first&.content&.truncate(60).presence || "New conversation"
  end
end
```

```ruby
# app/models/agent_message.rb
class AgentMessage < ApplicationRecord
  ROLES = %w[user assistant tool_call tool_result error].freeze

  belongs_to :agent_conversation

  validates :role, inclusion: {in: ROLES}
  validates :content, presence: true, if: -> { role.in?(%w[user assistant]) }
  validates :tool_name, presence: true, if: -> { role.in?(%w[tool_call tool_result]) }
end
```

- [ ] **Step 4: Tests**

```ruby
# test/models/agent_conversation_test.rb
require "test_helper"

class AgentConversationTest < ActiveSupport::TestCase
  setup do
    @user = create(:onboarded_user)
    @team = @user.current_team
  end

  test "valid with team + user" do
    conv = AgentConversation.new(team: @team, user: @user)
    assert conv.valid?
  end

  test "destroying conversation destroys its messages" do
    conv = AgentConversation.create!(team: @team, user: @user)
    conv.agent_messages.create!(role: "user", content: "hello")
    assert_difference -> { AgentMessage.count }, -1 do
      conv.destroy
    end
  end

  test "derived_title falls back to first user message excerpt then default" do
    conv = AgentConversation.create!(team: @team, user: @user)
    assert_equal "New conversation", conv.derived_title
    conv.agent_messages.create!(role: "user", content: "Draft a newsletter about our new feature please")
    assert_match(/Draft a newsletter about our new feature please/, conv.derived_title)
    conv.update!(title: "Custom title")
    assert_equal "Custom title", conv.derived_title
  end
end
```

```ruby
# test/models/agent_message_test.rb
require "test_helper"

class AgentMessageTest < ActiveSupport::TestCase
  setup do
    @user = create(:onboarded_user)
    @team = @user.current_team
    @conv = AgentConversation.create!(team: @team, user: @user)
  end

  test "rejects invalid role" do
    msg = @conv.agent_messages.build(role: "invalid", content: "x")
    refute msg.valid?
    assert_match(/role/, msg.errors.full_messages.join)
  end

  test "user/assistant messages require content" do
    msg = @conv.agent_messages.build(role: "user")
    refute msg.valid?
  end

  test "tool_call/tool_result messages require tool_name, allow nil content" do
    msg = @conv.agent_messages.build(role: "tool_call", tool_name: "subscribers_count", tool_arguments: {})
    assert msg.valid?
  end

  test "error messages allow nil content" do
    msg = @conv.agent_messages.build(role: "error", error_class: "RuntimeError", error_message: "boom")
    assert msg.valid?
  end
end
```

- [ ] **Step 5: Run, expect green.**

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb app/models/agent_conversation.rb app/models/agent_message.rb test/models/agent_conversation_test.rb test/models/agent_message_test.rb
git commit -m "feat(agent): AgentConversation + AgentMessage models + migration"
```

---

## Task 2: `Agent::ToolAdapter` — bridge MCP tools into ruby_llm tool format

`ruby_llm` 1.15's tool-use takes tools defined as classes. We adapt our `Mcp::Tool::Base` descendants on the fly.

**Files:**
- Create: `app/services/agent/tool_adapter.rb`
- Create: `test/services/agent/tool_adapter_test.rb`

- [ ] **Step 1: Read `ruby_llm` tool API**

```bash
grep -rn "class Tool\|def description\|param" $(bundle show ruby_llm)/lib/ruby_llm/tool.rb 2>/dev/null | head -30
```

The pattern in `ruby_llm` 1.15 is:

```ruby
class MyTool < RubyLLM::Tool
  description "..."
  param :foo, type: :string, desc: "...", required: true

  def execute(foo:)
    {result: "..."}
  end
end
```

Tools are registered via `chat.with_tool(MyTool)` (or `with_tools(*classes)`).

- [ ] **Step 2: Failing test**

```ruby
# test/services/agent/tool_adapter_test.rb
require "test_helper"

module Agent
  class ToolAdapterTest < ActiveSupport::TestCase
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
    end

    test "adapts an Mcp::Tool::Base class into a RubyLLM::Tool subclass" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Team::GetCurrent, context: @ctx)
      assert adapted < RubyLLM::Tool
      assert_equal "team_get_current", adapted.name
    end

    test "adapted tool's #execute calls our tool's #invoke with context" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Team::GetCurrent, context: @ctx)
      result = adapted.new.execute({})
      assert_equal @team.id, result[:id]
    end

    test "adapt_all returns one wrapper class per loaded tool" do
      adapted = ToolAdapter.adapt_all(context: @ctx)
      assert adapted.is_a?(Array)
      assert(adapted.all? { |c| c < RubyLLM::Tool })
      assert_equal Mcp::Tool::Loader.load_all.size, adapted.size
    end
  end
end
```

- [ ] **Step 3: Implement**

```ruby
# app/services/agent/tool_adapter.rb
# frozen_string_literal: true

module Agent
  # Bridges Mcp::Tool::Base descendants into RubyLLM::Tool subclasses so the
  # in-app agent can use the same registry as the MCP server. Each adaptation
  # is per-context: the wrapper class closes over a specific Mcp::Tool::Context
  # so the running conversation's user + team scope every tool call.
  module ToolAdapter
    module_function

    def adapt_all(context:)
      Mcp::Tool::Loader.load_all.map { |t| adapt(t, context: context) }
    end

    def adapt(tool_class, context:)
      our_tool = tool_class
      ctx = context

      Class.new(RubyLLM::Tool) do
        define_singleton_method(:name) { our_tool.tool_name }
        description our_tool.description.to_s

        # ruby_llm's `param` DSL takes one arg per param. We translate the
        # JSON Schema's `properties` into individual `param` calls. Required
        # comes from the schema's `required` list.
        schema = our_tool.arguments_schema || {}
        required = Array(schema[:required] || schema["required"]).map(&:to_s)
        properties = schema[:properties] || schema["properties"] || {}
        properties.each do |key, prop|
          key_s = key.to_s
          ruby_type = json_schema_to_ruby_llm_type(prop[:type] || prop["type"])
          desc = prop[:description] || prop["description"] || ""
          param key_s.to_sym, type: ruby_type, desc: desc, required: required.include?(key_s)
        end

        define_method(:execute) do |args = {}|
          # ruby_llm passes args as a Hash with string OR symbol keys depending
          # on version; normalize to strings (our tools expect strings).
          string_args = args.transform_keys(&:to_s)
          our_tool.new.invoke(arguments: string_args, context: ctx)
        rescue ActiveRecord::RecordNotFound => e
          {error: "Not found: #{e.message}"}
        rescue Mcp::Tool::ArgumentError => e
          {error: "Invalid arguments: #{e.message}"}
        rescue => e
          {error: "#{e.class}: #{e.message}"}
        end
      end
    end

    def json_schema_to_ruby_llm_type(json_type)
      case json_type.to_s
      when "string" then :string
      when "integer" then :integer
      when "number" then :number
      when "boolean" then :boolean
      when "array" then :array
      when "object" then :object
      else :string
      end
    end
  end
end
```

> **CAVEAT:** The `param` DSL signature on `RubyLLM::Tool` may differ from the above (e.g. `:type` might be `:type:` with positional, not kwarg; or it may not support `:object` type at all). After implementation, run the adapter test — if it fails on the `param` call, adjust by reading `bundle show ruby_llm`/lib/ruby_llm/tool.rb. If `:object` type isn't supported, fall back to `:string` (the LLM will see a JSON-string param).

- [ ] **Step 4: Run, expect green.**

- [ ] **Step 5: Commit**

```bash
git add app/services/agent/tool_adapter.rb test/services/agent/tool_adapter_test.rb
git commit -m "feat(agent): Agent::ToolAdapter — adapts MCP tools to ruby_llm format"
```

---

## Task 3: `Agent::Runner` — orchestrates the turn loop

**Files:**
- Create: `app/services/agent/runner.rb`
- Create: `test/services/agent/runner_test.rb`

- [ ] **Step 1: Failing test**

```ruby
# test/services/agent/runner_test.rb
require "test_helper"

module Agent
  class RunnerTest < ActiveSupport::TestCase
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @conv = AgentConversation.create!(team: @team, user: @user)
      AI::Base.force_stub = true  # ensure LLM doesn't actually fire
    end

    teardown { AI::Base.force_stub = false }

    test "in stub mode (no LLM), persists user message then a stub assistant response" do
      events = []
      runner = Runner.new(conversation: @conv, on_event: ->(e) { events << e })
      runner.handle_user_message("How many subscribers do I have?")

      user_msg = @conv.agent_messages.where(role: "user").last
      assert_equal "How many subscribers do I have?", user_msg.content

      asst_msg = @conv.agent_messages.where(role: "assistant").last
      refute_nil asst_msg
      assert_match(/stub|not configured|missing/i, asst_msg.content)

      assert_includes events.map { |e| e[:type] }, :user_message
      assert_includes events.map { |e| e[:type] }, :assistant_message
    end

    test "when LLM is not configured, returns a 'configure your key' assistant message" do
      original = ::Llm::Configuration.singleton_class.instance_method(:current)
      ::Llm::Configuration.singleton_class.define_method(:current) { ::Llm::Configuration.new(credentials: {}, env: {}) }
      AI::Base.force_stub = false
      begin
        runner = Runner.new(conversation: @conv)
        runner.handle_user_message("hi")
        asst = @conv.agent_messages.where(role: "assistant").last
        assert_match(/not configured|configure/i, asst.content)
      ensure
        ::Llm::Configuration.singleton_class.define_method(:current, original)
      end
    end
  end
end
```

- [ ] **Step 2: Implement**

```ruby
# app/services/agent/runner.rb
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
      I'm not connected to an LLM right now. Set up your key in `credentials.llm.api_key`
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
      emit(type: :user_message, message_id: user_msg.id, content: content)

      unless ::Llm::Configuration.current.usable?
        return persist_assistant(NOT_CONFIGURED_MESSAGE)
      end

      respond_via_llm(content)
    rescue => e
      Rails.logger.error("[agent] runner failed: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      err_msg = @conversation.agent_messages.create!(role: "error", error_class: e.class.name, error_message: e.message)
      emit(type: :error, message_id: err_msg.id, message: "#{e.class}: #{e.message}")
    end

    private

    def respond_via_llm(content)
      tools = ToolAdapter.adapt_all(context: @context)
      chat = RubyLLM.chat(model: ::Llm::Configuration.current.default_model)
      chat = chat.with_tools(*tools) if tools.any?
      chat = chat.with_instructions(system_prompt)

      # Replay prior messages so the model has context.
      replay_history(chat)

      result = chat.ask(content)
      assistant_text = result.respond_to?(:content) ? result.content : result.to_s
      persist_assistant(assistant_text.to_s)
    end

    def replay_history(chat)
      # Skip the just-created user message (we'll send it via #ask). Replay
      # the rest as alternating user/assistant turns. ruby_llm's exact API
      # for prepending history varies — if `chat.add_message(role:, content:)`
      # exists use that; otherwise build a transcript string and prepend it
      # to the system prompt. For v1, simplest: don't replay (each turn is
      # stateless). Document and revisit when conversations get long enough
      # for memory to matter.
      # Intentionally a no-op for v1.
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
      emit(type: :assistant_message, message_id: msg.id, content: text)
      msg
    end

    def emit(payload)
      @on_event&.call(payload)
    end
  end
end
```

- [ ] **Step 3: Run, expect green** (in stub mode the LLM call shouldn't fire; the "not configured" branch handles the test cases).

> **CAVEAT:** `AI::Base.force_stub` doesn't affect `RubyLLM.chat` — that's only for `AI::*` services. The runner test in stub mode will actually attempt to call ruby_llm's chat. To make this test reliable without an API key, we may need to ALSO stub `RubyLLM.chat` to return a canned response. Approach: replace the `respond_via_llm` body with a guard that checks `AI::Base.force_stub` and returns a fixed stub message in that case:
>
> ```ruby
> def respond_via_llm(content)
>   if AI::Base.force_stub
>     return persist_assistant("(stub agent reply — AI::Base.force_stub is set)")
>   end
>   # ...real path
> end
> ```
>
> This isn't elegant (force_stub leaking from AI:: into Agent::), but it keeps tests reliable. A cleaner v2 would have `Agent::Runner.force_stub` of its own.

- [ ] **Step 4: Commit**

```bash
git add app/services/agent/runner.rb test/services/agent/runner_test.rb
git commit -m "feat(agent): Agent::Runner — orchestrates conversation turn loop"
```

---

## Task 4: `AgentChannel` — ActionCable channel for streaming

**Files:**
- Create: `app/channels/agent_channel.rb`
- Create: `test/channels/agent_channel_test.rb`

- [ ] **Step 1: Implement**

```ruby
# app/channels/agent_channel.rb
class AgentChannel < ApplicationCable::Channel
  def subscribed
    conversation = AgentConversation.find_by(id: params[:conversation_id])
    if conversation.nil? || conversation.user_id != current_user.id
      reject
      return
    end

    @conversation = conversation
    stream_for conversation
  end

  # Client publishes user messages over the channel. Runner streams events
  # back via broadcast_to.
  def send_message(data)
    return if @conversation.nil?
    Agent::Runner.new(
      conversation: @conversation,
      on_event: ->(event) { AgentChannel.broadcast_to(@conversation, event) }
    ).handle_user_message(data["content"].to_s)
  end
end
```

- [ ] **Step 2: Confirm `ApplicationCable::Channel` exists and `current_user` is wired**

```bash
cat app/channels/application_cable/channel.rb
cat app/channels/application_cable/connection.rb
```

If `current_user` isn't wired in the connection, do that:

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # In Devise apps, this looks up the user from the encrypted session cookie.
      env["warden"].user || reject_unauthorized_connection
    end
  end
end
```

If the file already has Devise-aware auth, leave it. If not, write the version above.

- [ ] **Step 3: Commit**

```bash
git add app/channels/agent_channel.rb app/channels/application_cable/connection.rb
git commit -m "feat(agent): AgentChannel + Devise-aware Cable auth"
```

(Channel tests in Rails are hairy and provide low value here — manual smoke is better. Skip a unit test for the channel; the runner test covers the runner; integration smoke covers the wire path.)

---

## Task 5: Controllers + routes

**Files:**
- Create: `app/controllers/account/agent_conversations_controller.rb`
- Create: `app/controllers/account/agent_messages_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Routes**

In `config/routes.rb`, find the `account_navigation` block (the BulletTrain `account` namespace). Add:

```ruby
resources :agent_conversations, only: [:index, :show, :create, :destroy] do
  resources :agent_messages, only: [:create]
end
```

These routes need to be inside the BulletTrain account namespace so the auth + team scoping are applied.

- [ ] **Step 2: AgentConversationsController**

```ruby
# app/controllers/account/agent_conversations_controller.rb
class Account::AgentConversationsController < Account::ApplicationController
  account_load_and_authorize_resource :agent_conversation, through: :team, through_association: :agent_conversations

  def index
    @agent_conversations = current_team.agent_conversations.where(user_id: current_user.id).order(updated_at: :desc)
  end

  def show
    @messages = @agent_conversation.agent_messages
  end

  def create
    @agent_conversation.user = current_user
    if @agent_conversation.save
      redirect_to [:account, @agent_conversation]
    else
      redirect_to [:account, :agent_conversations], alert: "Could not start conversation"
    end
  end

  def destroy
    @agent_conversation.destroy
    redirect_to [:account, :agent_conversations], notice: "Conversation deleted"
  end
end
```

- [ ] **Step 3: AgentMessagesController** — non-Cable fallback (used by progressive enhancement before JS connects, or if Cable isn't available)

```ruby
# app/controllers/account/agent_messages_controller.rb
class Account::AgentMessagesController < Account::ApplicationController
  before_action :load_conversation

  def create
    Agent::Runner.new(conversation: @agent_conversation).handle_user_message(params[:content].to_s)
    respond_to do |format|
      format.html { redirect_to [:account, @agent_conversation] }
      format.json { render json: {ok: true} }
    end
  end

  private

  def load_conversation
    @agent_conversation = current_team.agent_conversations.where(user_id: current_user.id).find(params[:agent_conversation_id])
  end
end
```

- [ ] **Step 4: Add `has_many :agent_conversations` on Team and User models**

Edit `app/models/team.rb` to add:
```ruby
has_many :agent_conversations, dependent: :destroy
```

Edit `app/models/user.rb` similarly:
```ruby
has_many :agent_conversations, dependent: :destroy
```

- [ ] **Step 5: Cancan ability** — make sure users can read/write their own conversations on their team. Check `app/models/ability.rb`. Add (inside the team-loaded ability block):

```ruby
can :manage, AgentConversation, team_id: team.id, user_id: user.id
can :manage, AgentMessage, agent_conversation: {team_id: team.id, user_id: user.id}
```

(If the existing ability uses different syntax for nested/scoped permissions, follow that style.)

- [ ] **Step 6: Run controller tests** if any are scaffolded; else just smoke via `bin/rails routes | grep agent` to confirm routes exist.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/account/agent_conversations_controller.rb app/controllers/account/agent_messages_controller.rb config/routes.rb app/models/team.rb app/models/user.rb app/models/ability.rb
git commit -m "feat(agent): controllers + routes + ability for AgentConversations"
```

---

## Task 6: Stimulus controller `agent_chat_controller.js`

**Files:**
- Create: `app/javascript/controllers/agent_chat_controller.js`

- [ ] **Step 1: Implement**

```javascript
// app/javascript/controllers/agent_chat_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Wires the right-side agent chat panel.
//
//   <aside data-controller="agent-chat"
//          data-agent-chat-conversation-id-value="<%= conv.id %>"
//          data-agent-chat-csrf-value="<%= form_authenticity_token %>">
//     <button data-action="click->agent-chat#toggle">Chat</button>
//     <div data-agent-chat-target="messages"></div>
//     <form data-action="submit->agent-chat#submit">
//       <textarea data-agent-chat-target="input"></textarea>
//       <button type="submit">Send</button>
//     </form>
//   </aside>
export default class extends Controller {
  static targets = ["messages", "input", "panel"]
  static values = { conversationId: Number, csrf: String }

  connect() {
    if (!this.hasConversationIdValue) return
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "AgentChannel", conversation_id: this.conversationIdValue },
      {
        received: (event) => this.handleEvent(event),
        connected: () => console.debug("[agent-chat] connected"),
        rejected: () => console.warn("[agent-chat] rejected — auth?")
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  toggle() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.toggle("hidden")
  }

  submit(e) {
    e.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text) return
    this.subscription.perform("send_message", { content: text })
    this.inputTarget.value = ""
  }

  handleEvent(event) {
    if (!this.hasMessagesTarget) return
    const node = document.createElement("div")
    node.className = `agent-chat-msg agent-chat-msg--${event.type}`
    if (event.type === "user_message" || event.type === "assistant_message") {
      node.textContent = event.content
    } else if (event.type === "tool_call") {
      node.textContent = `→ ${event.tool_name}(${JSON.stringify(event.arguments || {})})`
    } else if (event.type === "tool_result") {
      node.textContent = `← ${event.tool_name}: ${JSON.stringify(event.result || {}).slice(0, 200)}`
    } else if (event.type === "error") {
      node.textContent = `error: ${event.message}`
    } else {
      node.textContent = JSON.stringify(event)
    }
    this.messagesTarget.appendChild(node)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }
}
```

- [ ] **Step 2: Confirm `@rails/actioncable` is available**

```bash
grep -E '"@rails/actioncable"|actioncable' package.json
```

If missing, add it:

```bash
yarn add @rails/actioncable  # or npm install
```

- [ ] **Step 3: Verify the controller loads without errors**

```bash
bin/dev > /tmp/dev.log 2>&1 &
sleep 8
# Open http://localhost:3000 in a browser; check console for "[agent-chat]" logs
pkill -9 -f "puma\|bin/dev\|foreman" 2>/dev/null
```

(This is mostly visual; full integration verified in Task 8.)

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/agent_chat_controller.js package.json yarn.lock
git commit -m "feat(agent): Stimulus controller for the agent chat panel"
```

---

## Task 7: Side panel partial + integrate into account layout

**Files:**
- Create: `app/views/account/agent_conversations/_panel.html.erb`
- Create: `app/views/account/agent_conversations/_message.html.erb`
- Create: `app/views/account/agent_conversations/index.html.erb` (a list of past conversations + "new")
- Create: `app/views/account/agent_conversations/show.html.erb`
- Modify: `app/views/themes/light/layouts/_account.html.erb` — render the panel

The visual treatment must match `DESIGN.md`:
- Hairline borders, white card chrome, Geist Sans
- Orange accent for primary CTAs, zinc for everything else
- Mono caps for eyebrow labels (e.g., `AGENT · CONVERSATION 12 · 5 MESSAGES`)

- [ ] **Step 1: Read `DESIGN.md`** for the design rules. Read `app/views/themes/light/layouts/_account.html.erb` to understand where to inject the panel.

- [ ] **Step 2: `_panel.html.erb`** (~80 lines, design-spec-conformant). Right-side fixed-position aside, hidden by default, toggled by a button in the top nav. The button itself is added to `_account.html.erb`'s header.

- [ ] **Step 3: `_message.html.erb`** — single message bubble. Render differently based on `role`:
  - `user`: zinc background, right-aligned
  - `assistant`: white background, hairline border, left-aligned
  - `tool_call`: small mono text "→ tool_name(args)"
  - `tool_result`: small mono text "← tool_name: result excerpt"
  - `error`: rose-tinted border + text

- [ ] **Step 4: `index.html.erb`** — list past conversations with a "New conversation" CTA.

- [ ] **Step 5: `show.html.erb`** — full-page chat view (alternative to the side panel; useful for long conversations).

- [ ] **Step 6: Commit**

```bash
git add app/views/account/agent_conversations/ app/views/themes/light/layouts/_account.html.erb
git commit -m "feat(agent): right-side chat panel + index + show views"
```

---

## Task 8: End-to-end smoke

- [ ] **Step 1:** Start dev server, sign in as `qa@local.test`, click the agent panel button, send "How many subscribers do I have?" and verify a response renders. The response may be a stub (no LLM key) but the wire-level should work: user message persists, assistant message appears.

- [ ] **Step 2:** Run all tests: `bin/rails test`.

- [ ] **Step 3:** If anything is broken, debug. Common issues: Cable connection authentication, Stimulus controller not loading (esbuild bundle issue), CSRF on non-Cable controller fallback.

---

## Self-review

**Spec coverage:**
- [x] Conversation models + persistence — Task 1
- [x] Tools shared with MCP via in-process adapter — Task 2
- [x] Runner orchestrates turn loop with ruby_llm — Task 3
- [x] ActionCable streaming — Task 4
- [x] Controllers + routes — Task 5
- [x] Stimulus controller for the chat panel — Task 6
- [x] Side panel UI conformant with DESIGN.md — Task 7
- [x] Graceful degradation when no LLM (Runner returns "not configured" message) — Task 3

**Type / name consistency:** `Agent::ToolAdapter` + `Agent::Runner`; `AgentConversation` + `AgentMessage` (singular) per Rails convention; routes nested under `agent_conversations`.

**Implementation deviations expected:**
- `RubyLLM::Tool` `param` DSL signature — verify after Task 2's first run.
- `RubyLLM.chat#with_tools` may not exist; could be `with_tool` (singular, called multiple times). Check at Task 3's first run.
- ruby_llm's response object shape (`result.content` vs `result.text`) — adapt at Task 3.
- DESIGN.md compliance on Task 7 is judgment-heavy; better to ship a minimal panel and iterate than to over-engineer.
