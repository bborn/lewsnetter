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
