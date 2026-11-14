# frozen_string_literal: true

require "test_helper"

module AI
  class BaseTest < ActiveSupport::TestCase
    class Plain < AI::Base
    end

    class PinnedModel < AI::Base
      private

      def model_id
        "claude-opus-4-1"
      end
    end

    setup do
      @original_current = ::Llm::Configuration.singleton_class.instance_method(:current)
      @original_chat = RubyLLM.singleton_class.instance_method(:chat)
      @chat_kwargs = nil
      captured = ->(kwargs) { @chat_kwargs = kwargs }
      RubyLLM.singleton_class.define_method(:chat) { |**kwargs| captured.call(kwargs) && :fake_chat }
    end

    teardown do
      ::Llm::Configuration.singleton_class.define_method(:current, @original_current)
      RubyLLM.singleton_class.define_method(:chat, @original_chat)
    end

    test "the chat uses LLM_DEFAULT_MODEL when it is set" do
      use_config(env: {"LLM_DEFAULT_MODEL" => "claude-haiku-4-5"},
        credentials: {llm: {default_model: "claude-opus-4-1"}})

      Plain.new.send(:chat)

      assert_equal({model: "claude-haiku-4-5"}, @chat_kwargs)
    end

    test "the chat uses credentials.llm.default_model when ENV is unset" do
      use_config(env: {}, credentials: {llm: {default_model: "claude-opus-4-1"}})

      Plain.new.send(:chat)

      assert_equal({model: "claude-opus-4-1"}, @chat_kwargs)
    end

    test "the chat falls back to the application default with nothing configured" do
      use_config(env: {}, credentials: {})

      Plain.new.send(:chat)

      assert_equal({model: ::Llm::Configuration::DEFAULT_MODEL}, @chat_kwargs)
    end

    test "a subclass that overrides model_id still wins over configuration" do
      use_config(env: {"LLM_DEFAULT_MODEL" => "claude-haiku-4-5"}, credentials: {})

      PinnedModel.new.send(:chat)

      assert_equal({model: "claude-opus-4-1"}, @chat_kwargs)
    end

    test "ask_llm with a schema asks for structured output and returns the parsed answer" do
      fake = FakeChat.new(content: '{"a":1}', parsed: {"a" => 1})
      service = Plain.new
      service.instance_variable_set(:@chat, fake)

      assert_equal({"a" => 1}, service.send(:ask_llm, system: "sys", user: "hi", schema: :the_schema))
      assert_equal [[:with_instructions, "sys"], [:with_schema, :the_schema], [:ask, "hi"]], fake.calls
    end

    test "ask_llm without a schema returns the response text" do
      fake = FakeChat.new(content: "plain text", parsed: nil)
      service = Plain.new
      service.instance_variable_set(:@chat, fake)

      assert_equal "plain text", service.send(:ask_llm, system: "sys", user: "hi")
      assert_not_includes fake.calls.map(&:first), :with_schema
    end

    test "ask_llm returns nil when the call raises" do
      fake = FakeChat.new(content: nil, parsed: nil)
      fake.define_singleton_method(:ask) { |_| raise RubyLLM::Error, "boom" }
      service = Plain.new
      service.instance_variable_set(:@chat, fake)

      assert_nil service.send(:ask_llm, system: "sys", user: "hi", schema: :the_schema)
    end

    # Records the RubyLLM::Chat calls ask_llm makes.
    class FakeChat
      Response = Struct.new(:content, :parsed)
      attr_reader :calls

      def initialize(content:, parsed:)
        @response = Response.new(content, parsed)
        @calls = []
      end

      def with_instructions(text)
        @calls << [:with_instructions, text]
        self
      end

      def with_schema(schema)
        @calls << [:with_schema, schema]
        self
      end

      def ask(text)
        @calls << [:ask, text]
        @response
      end
    end

    private

    def use_config(env:, credentials:)
      config = ::Llm::Configuration.new(credentials: credentials, env: env)
      ::Llm::Configuration.singleton_class.define_method(:current) { config }
    end
  end
end
