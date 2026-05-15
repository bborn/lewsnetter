# frozen_string_literal: true

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

      # Event types are strings ("#{role}_message") so they survive JSON
      # serialization over ActionCable.
      assert_includes events.map { |e| e[:type] }, "user_message"
      assert_includes events.map { |e| e[:type] }, "assistant_message"
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
