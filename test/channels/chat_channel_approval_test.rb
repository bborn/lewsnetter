# frozen_string_literal: true

require "test_helper"
require "ruby_llm/test_helper"

# Tools that declare requires_approval wait in the chat until the user
# answers. The model's replies are scripted, so the real ruby_llm loop runs
# without a provider.
class ChatChannelApprovalTest < ActionCable::Channel::TestCase
  include RubyLLM::TestHelper

  tests ChatChannel

  setup do
    @original_current = Llm::Configuration.singleton_class.instance_method(:current)
    Llm::Configuration.singleton_class.define_method(:current) do
      Llm::Configuration.new(credentials: {}, env: {"ANTHROPIC_API_KEY" => "test-key"})
    end

    owner = create(:onboarded_user)
    @team = owner.current_team
    @user = create(:onboarded_user)
    @membership = create(:membership, team: @team, user: @user, role_ids: [Role.admin.id])
    # An existing registry row keeps acts_as_chat from resolving a model,
    # which needs a provider key.
    model = RubyLLM::ActiveRecord::Model.create!(model_id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic")
    @chat = @team.chats.create!(user: @user, model: model)
    @campaign = create(:campaign, team: @team, subject: "Spring launch")

    stub_connection current_user: @user
    subscribe chat_id: @chat.id
  end

  teardown do
    Llm::Configuration.singleton_class.define_method(:current, @original_current)
  end

  def ask_to_delete_campaign
    stub_replies tool_call(:campaigns_delete, id: @campaign.id), "Deleted it."
    perform :send_message, content: "delete the spring campaign"
  end

  def pending_approval
    @chat.pending_questions.find(&:approval?)
  end

  def last_reply
    @chat.messages.where(role: "assistant").order(:id).last.content
  end

  def tool_results
    @chat.messages.where(role: "tool").order(:id).map(&:content)
  end

  def events(type)
    broadcasts(ChatChannel.broadcasting_for(ChatChannel.stream_key(@chat))).map { |payload| JSON.parse(payload) }.select { |e| e["type"] == type }
  end

  test "a delete waits for the user instead of running in the same turn" do
    ask_to_delete_campaign

    assert Campaign.exists?(@campaign.id)
    assert_equal "campaigns_delete", pending_approval.tool_call.name
    assert_empty tool_results
  end

  test "the panel gets the pending call with what it would do" do
    ask_to_delete_campaign

    request = events("approval_request").sole
    assert_equal pending_approval.id, request["tool_call_id"]
    assert_includes request["html"], "Delete campaign &quot;Spring launch&quot;"
    assert_includes request["html"], "Approve"
  end

  test "approving runs the call and finishes the reply" do
    ask_to_delete_campaign
    perform :approve, tool_call_id: pending_approval.id

    assert_not Campaign.exists?(@campaign.id)
    assert_nil pending_approval
    assert_equal "Deleted it.", last_reply
    assert_equal [true], events("approval_decided").map { |e| e["approved"] }
    # The resumed turn has no new user message to show.
    assert_equal 1, events("message_full").count { |e| e["role"] == "user" }
  end

  test "approving twice runs the call once" do
    ask_to_delete_campaign
    id = pending_approval.id
    perform :approve, tool_call_id: id
    perform :approve, tool_call_id: id

    assert_equal 1, tool_results.size
    assert_equal "Deleted it.", last_reply
  end

  test "declining never runs the call and tells the model why" do
    stub_replies tool_call(:campaigns_delete, id: @campaign.id), "Understood, I left it."
    perform :send_message, content: "delete the spring campaign"
    perform :decline, tool_call_id: pending_approval.id

    assert Campaign.exists?(@campaign.id)
    assert_nil pending_approval
    assert_includes tool_results.sole, ChatChannel::DECLINED_NOTE
    assert_equal "Understood, I left it.", last_reply
    assert_equal [false], events("approval_decided").map { |e| e["approved"] }
  end

  test "a new message declines the pending call and still gets an answer" do
    ask_to_delete_campaign
    stub_replies "Okay, I left it."
    perform :send_message, content: "actually, never mind"

    assert Campaign.exists?(@campaign.id)
    assert_nil pending_approval
    assert_includes tool_results.sole, ChatChannel::MOVED_ON_NOTE
    assert_equal "Okay, I left it.", last_reply
  end

  test "someone who has left the team can't approve" do
    ask_to_delete_campaign
    @membership.nullify_user
    perform :approve, tool_call_id: pending_approval.id

    assert Campaign.exists?(@campaign.id)
    assert pending_approval
  end

  test "approving after losing the role leaves the record alone" do
    ask_to_delete_campaign
    Membership.find(@membership.id).update!(role_ids: [])
    perform :approve, tool_call_id: pending_approval.id

    assert Campaign.exists?(@campaign.id)
    assert_includes tool_results.sole, Mcp::Tool::Base::NOT_ALLOWED
  end

  test "tools that don't declare requires_approval still run in the same turn" do
    stub_replies tool_call(:campaigns_list), "You have one campaign."
    perform :send_message, content: "list campaigns"

    assert_empty @chat.pending_questions
    assert_equal 1, tool_results.size
    assert_equal "You have one campaign.", last_reply
    assert_empty events("approval_request")
  end
  test "an approve that loses the race to a decline in another tab keeps the decline" do
    ask_to_delete_campaign
    # The approve read the call as pending, then another tab declined it
    # before the approve recorded its decision.
    stale = pending_approval
    @chat.decline(stale, "no")
    subscription.define_singleton_method(:pending_approvals) { [stale] }
    stub_replies "Okay."
    perform :approve, tool_call_id: stale.id

    assert Campaign.exists?(@campaign.id)
  end

  test "a call on another chat can't be approved from this one" do
    other_chat = @team.chats.create!(user: create(:onboarded_user), model: @chat.model)
    ask_to_delete_campaign
    forged = pending_approval
    forged_row = RubyLLM::ActiveRecord::ToolCall.find_by!(tool_call_id: forged.id)
    forged_row.message.update!(chat_id: other_chat.id)

    perform :approve, tool_call_id: forged.id

    assert Campaign.exists?(@campaign.id)
    assert_equal "pending", forged_row.reload.approval
  end

  test "a pending call can be approved after a reload" do
    ask_to_delete_campaign
    unsubscribe
    subscribe chat_id: @chat.id
    perform :approve, tool_call_id: pending_approval.id

    assert_not Campaign.exists?(@campaign.id)
    assert_equal "Deleted it.", last_reply
  end
end
