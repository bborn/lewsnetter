# frozen_string_literal: true

require "test_helper"

class ChatChannelTest < ActionCable::Channel::TestCase
  # Keep every turn on the "LLM not configured" path so no test reaches a
  # provider, whatever credentials the machine running it has.
  setup do
    @original_current = Llm::Configuration.singleton_class.instance_method(:current)
    Llm::Configuration.singleton_class.define_method(:current) { Llm::Configuration.new(credentials: {}, env: {}) }

    @admin = create(:onboarded_user)
    @team = @admin.current_team
    @member = create(:onboarded_user)
    @membership = create(:membership, team: @team, user: @member)
    # An existing registry row keeps acts_as_chat from resolving a model,
    # which needs a provider key.
    model = Model.create!(model_id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic")
    @chat = @team.chats.create!(user: @member, model: model)
  end

  teardown do
    Llm::Configuration.singleton_class.define_method(:current, @original_current)
  end

  test "the chat's owner, while a team member, can subscribe" do
    stub_connection current_user: @member
    subscribe chat_id: @chat.id

    assert subscription.confirmed?
    assert_has_stream_for @chat
  end

  test "another member of the same team cannot subscribe to someone else's chat" do
    stub_connection current_user: @admin
    subscribe chat_id: @chat.id

    assert subscription.rejected?
  end

  test "an unknown chat id is rejected" do
    stub_connection current_user: @member
    subscribe chat_id: 0

    assert subscription.rejected?
  end

  test "a member removed from the team cannot subscribe to their old chat" do
    @membership.nullify_user

    stub_connection current_user: @member.reload
    subscribe chat_id: @chat.id

    assert subscription.rejected?, "a removed member must lose agent access to the team"
  end

  test "an open subscription stops working once the member is removed" do
    stub_connection current_user: @member
    subscribe chat_id: @chat.id
    assert subscription.confirmed?

    @membership.nullify_user

    assert_no_difference -> { Message.count } do
      perform :send_message, content: "list subscribers"
    end
    assert_empty subscription.streams, "the revoked subscription must stop streaming"
    assert_no_difference -> { Message.count } do
      perform :send_message, content: "and again"
    end
  end

  test "a member of several teams can use the chat of a team that is not their current one" do
    assert_not_equal @team, @member.current_team

    stub_connection current_user: @member
    subscribe chat_id: @chat.id
    assert subscription.confirmed?

    assert_difference -> { @chat.messages.count }, 2 do
      perform :send_message, content: "hello"
    end
  end
end
