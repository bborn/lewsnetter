# frozen_string_literal: true

require "test_helper"

module Llm
  class ConfigurationTest < ActiveSupport::TestCase
    test "with no credentials and no ENV, usable? is false" do
      config = Configuration.new(credentials: {}, env: {})
      refute config.usable?
      assert_nil config.api_key
      assert_equal :anthropic, config.provider
      assert_equal "claude-sonnet-4-6", config.default_model
      assert_nil config.base_url
    end

    test "reads from credentials.llm namespace" do
      creds = {llm: {provider: "cloudflare", api_key: "sk-cf-test", base_url: "https://gateway.example.com/v1/anthropic", default_model: "claude-haiku-4-5"}}
      config = Configuration.new(credentials: creds, env: {})
      assert config.usable?
      assert_equal "sk-cf-test", config.api_key
      assert_equal :cloudflare, config.provider
      assert_equal "https://gateway.example.com/v1/anthropic", config.base_url
      assert_equal "claude-haiku-4-5", config.default_model
    end

    test "falls back to credentials.anthropic.api_key when llm namespace absent (backwards compat)" do
      creds = {anthropic: {api_key: "sk-ant-old"}}
      config = Configuration.new(credentials: creds, env: {})
      assert config.usable?
      assert_equal "sk-ant-old", config.api_key
      assert_equal :anthropic, config.provider
    end

    test "ENV ANTHROPIC_API_KEY overrides credentials" do
      creds = {llm: {api_key: "from-creds"}}
      env = {"ANTHROPIC_API_KEY" => "from-env"}
      config = Configuration.new(credentials: creds, env: env)
      assert_equal "from-env", config.api_key
    end

    test "ENV LLM_BASE_URL overrides credentials base_url" do
      creds = {llm: {api_key: "k", base_url: "https://creds.example.com"}}
      env = {"LLM_BASE_URL" => "https://env.example.com"}
      config = Configuration.new(credentials: creds, env: env)
      assert_equal "https://env.example.com", config.base_url
    end

    test ".current returns a Configuration built from app credentials + ENV" do
      assert_kind_of Configuration, Configuration.current
    end
  end
end
