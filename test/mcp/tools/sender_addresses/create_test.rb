# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module SenderAddresses
      class CreateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        # Temporarily replaces Ses::IdentityChecker.new with a factory that
        # calls the given block (receiving the sender_address kwarg) and returns
        # a stub object whose #call runs the block's return value as a proc.
        def with_checker_stub(on_call:, &test_block)
          Ses::IdentityChecker.singleton_class.class_eval do
            alias_method :_orig_new, :new unless method_defined?(:_orig_new)
            define_method(:new) do |sender_address:|
              stub = Object.new
              stub.define_singleton_method(:call) { on_call.call(sender_address) }
              stub
            end
          end
          test_block.call
        ensure
          Ses::IdentityChecker.singleton_class.class_eval do
            if method_defined?(:_orig_new)
              alias_method :new, :_orig_new
              remove_method :_orig_new
            end
          end
        end

        test "creates sender address and returns ses_check with verified status" do
          with_checker_stub(on_call: ->(sa) { sa.update!(verified: true, ses_status: "success") }) do
            result = Create.new.invoke(
              arguments: {"email" => "new@example.com", "name" => "New Sender"},
              context: @ctx
            )
            assert_equal "new@example.com", result[:sender_address][:email]
            assert_equal "New Sender", result[:sender_address][:name]
            assert_equal true, result[:ses_check][:ok]
            assert_equal "success", result[:ses_check][:status]
            assert_nil result[:ses_check][:message]
            assert @team.sender_addresses.exists?(email: "new@example.com")
          end
        end

        test "record is saved even when SES is not configured" do
          with_checker_stub(on_call: ->(_sa) { raise Ses::ClientFor::NotConfigured, "No SES config" }) do
            result = Create.new.invoke(
              arguments: {"email" => "unconfigured@example.com"},
              context: @ctx
            )
            assert @team.sender_addresses.exists?(email: "unconfigured@example.com")
            assert_equal false, result[:ses_check][:ok]
            assert_equal "unconfigured", result[:ses_check][:status]
            assert_match "No SES config", result[:ses_check][:message]
          end
        end

        test "record is saved and ses_check returns error on unexpected checker exception" do
          with_checker_stub(on_call: ->(_sa) { raise RuntimeError, "Network timeout" }) do
            result = Create.new.invoke(
              arguments: {"email" => "error@example.com"},
              context: @ctx
            )
            assert @team.sender_addresses.exists?(email: "error@example.com")
            assert_equal false, result[:ses_check][:ok]
            assert_equal "error", result[:ses_check][:status]
            assert_match "Network timeout", result[:ses_check][:message]
          end
        end

        test "scopes creation to calling team" do
          with_checker_stub(on_call: ->(_sa) {}) do
            other_user = create(:onboarded_user)
            other_ctx = Mcp::Tool::Context.new(user: other_user, team: other_user.current_team)
            Create.new.invoke(arguments: {"email" => "theirs@example.com"}, context: other_ctx)
            Create.new.invoke(arguments: {"email" => "ours@example.com"}, context: @ctx)
            assert @team.sender_addresses.exists?(email: "ours@example.com")
            refute @team.sender_addresses.exists?(email: "theirs@example.com")
          end
        end
      end
    end
  end
end
