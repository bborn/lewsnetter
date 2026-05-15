require "test_helper"

class Account::AgentConversationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    @team = @user.current_team
    sign_in @user
    AI::Base.force_stub = true
  end

  teardown { AI::Base.force_stub = false }

  test "create with starter_prompt persists the prompt as a user message and runs the agent" do
    assert_difference -> { AgentConversation.count }, 1 do
      post account_team_agent_conversations_path(@team), params: {agent_conversation: {}, starter_prompt: "Draft a newsletter for me."}
    end
    conv = AgentConversation.last
    assert_equal @user.id, conv.user_id
    assert_equal @team.id, conv.team_id
    assert conv.agent_messages.where(role: "user").exists?(content: "Draft a newsletter for me.")
    assert conv.agent_messages.where(role: "assistant").exists?  # stub reply, but present
    assert_redirected_to [:account, conv]
  end

  test "create without starter_prompt just creates an empty conversation" do
    post account_team_agent_conversations_path(@team), params: {agent_conversation: {}}
    conv = AgentConversation.last
    assert_equal 0, conv.agent_messages.count
  end
end
