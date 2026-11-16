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
