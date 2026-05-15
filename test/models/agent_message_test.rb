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
    assert_match(/role/i, msg.errors.full_messages.join)
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
