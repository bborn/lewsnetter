# frozen_string_literal: true

require "test_helper"
require "ruby_llm/test_helper"

class Account::ChatsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include RubyLLM::TestHelper

  setup do
    # The layout renders the agent panel only while an LLM is configured.
    @original_current = Llm::Configuration.singleton_class.instance_method(:current)
    Llm::Configuration.singleton_class.define_method(:current) do
      Llm::Configuration.new(credentials: {}, env: {"ANTHROPIC_API_KEY" => "test-key"})
    end

    @user = create(:onboarded_user)
    @team = @user.current_team
    model = RubyLLM::ActiveRecord::Model.create!(model_id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic")
    @chat = @team.chats.create!(user: @user, model: model)
    sign_in @user
  end

  teardown do
    Llm::Configuration.singleton_class.define_method(:current, @original_current)
  end

  test "the index lists the user's chats and the start button" do
    @chat.messages.create!(role: "user", content: "Draft the spring newsletter")

    get account_team_chats_url(@team)

    assert_response :success
    assert_select "a[href='#{account_chat_path(@chat)}']", text: "Draft the spring newsletter"
    assert_select "button", text: "Start new chat"
  end

  test "the index says so when the user has no chats" do
    @chat.destroy!
    # The layout's panel would create a chat as the page renders; turn it
    # off so the list really is empty.
    Llm::Configuration.singleton_class.define_method(:current, @original_current)

    get account_team_chats_url(@team)

    assert_response :success
    assert_select "div", text: "NO CHATS YET"
  end

  test "the show page renders the conversation and the reply box" do
    @chat.messages.create!(role: "user", content: "Draft the spring newsletter")
    @chat.messages.create!(role: "assistant", content: "Here is a **draft**.")

    get account_chat_url(@chat)

    assert_response :success
    assert_select "div[data-controller='agent-chat'][data-agent-chat-chat-id-value='#{@chat.id}']" do
      assert_select "[data-agent-chat-target='messages']" do
        assert_select "div", text: "Draft the spring newsletter"
        assert_select "strong", text: "draft"
      end
      assert_select "textarea[data-agent-chat-target='input']"
      assert_select "button[type='submit']", text: "Send"
    end
  end

  test "the show page keeps a pending approval's buttons after a reload" do
    campaign = create(:campaign, team: @team, subject: "Spring launch")
    stub_replies tool_call(:campaigns_delete, id: campaign.id), "Deleted it."
    context = Mcp::Tool::Context.new(user: @user, team: @team)
    @chat.with_tools(*Chats::ToolAdapter.adapt_all(context: context))
    @chat.ask("delete the spring campaign")
    pending = @chat.pending_questions.sole

    get account_chat_url(@chat)

    assert_response :success
    # The side panel is an <aside>; this is the page's own chat.
    assert_select "div[data-controller='agent-chat'] [data-agent-chat-target='messages'] [data-approval-id='#{pending.id}']" do
      assert_select "button[data-action='agent-chat#approve']", text: "Approve"
      assert_select "button[data-action='agent-chat#decline']", text: "Decline"
    end
  end

  # The approval lives on the tool call row, so a reload still shows it.
  test "a call waiting for approval keeps its buttons in the agent panel after a reload" do
    campaign = create(:campaign, team: @team, subject: "Spring launch")
    stub_replies tool_call(:campaigns_delete, id: campaign.id), "Deleted it."
    context = Mcp::Tool::Context.new(user: @user, team: @team)
    @chat.with_tools(*Chats::ToolAdapter.adapt_all(context: context))
    @chat.ask("delete the spring campaign")
    pending = @chat.pending_questions.sole

    get account_team_chats_url(@team)

    assert_response :success
    assert_select "aside[data-controller='agent-chat'] [data-approval-id='#{pending.id}']" do
      assert_select "div", text: %(Delete campaign "Spring launch" (##{campaign.id}))
      assert_select "button[data-action='agent-chat#approve']", text: "Approve"
      assert_select "button[data-action='agent-chat#decline']", text: "Decline"
    end
  end
end
