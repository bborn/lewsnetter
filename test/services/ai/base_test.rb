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

    private

    def use_config(env:, credentials:)
      config = ::Llm::Configuration.new(credentials: credentials, env: env)
      ::Llm::Configuration.singleton_class.define_method(:current) { config }
    end
  end
end
