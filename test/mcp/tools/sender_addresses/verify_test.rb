# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module SenderAddresses
      class VerifyTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sa = @team.sender_addresses.create!(email: "sender@example.com", name: "Sender")
        end

        # Stubs Ses::IdentityChecker.new for the duration of the block.
        # on_call receives (sender_address) and its return value is ignored;
        # side-effects (like update!) are the expected way to influence test state.
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

        # Stubs Ses::IdentityCreator.new for the duration of the block.
        # on_call receives (sender_address) and must return a Result struct.
        def with_creator_stub(on_call:, &test_block)
          Ses::IdentityCreator.singleton_class.class_eval do
            alias_method :_orig_new, :new unless method_defined?(:_orig_new)
            define_method(:new) do |sender_address:|
              stub = Object.new
              stub.define_singleton_method(:call) { on_call.call(sender_address) }
              stub
            end
          end
          test_block.call
        ensure
          Ses::IdentityCreator.singleton_class.class_eval do
            if method_defined?(:_orig_new)
              alias_method :new, :_orig_new
              remove_method :_orig_new
            end
          end
        end

        test "re-checks SES status without sending verification email" do
          checker_called_with = nil
          with_checker_stub(on_call: ->(sa) {
            checker_called_with = sa
            sa.update!(verified: true, ses_status: "domain_verified")
          }) do
            result = Verify.new.invoke(
              arguments: {"id" => @sa.id, "send_verification_email" => false},
              context: @ctx
            )
            assert_equal @sa.id, result[:sender_address][:id]
            assert_equal true, result[:sender_address][:verified]
            assert_equal false, result[:verification_triggered]
            assert_equal "domain_verified", result[:status]
            assert_equal @sa.id, checker_called_with.id
          end
        end

        test "sends verification email and re-checks when send_verification_email is true" do
          creator_result = Ses::IdentityCreator::Result.new(
            ok: true, status: "sent", message: "Verification email sent."
          )

          with_creator_stub(on_call: ->(_sa) { creator_result }) do
            with_checker_stub(on_call: ->(sa) { sa.update!(verified: false, ses_status: "pending") }) do
              result = Verify.new.invoke(
                arguments: {"id" => @sa.id, "send_verification_email" => true},
                context: @ctx
              )
              assert_equal true, result[:verification_triggered]
              assert_equal "sent", result[:status]
              assert_equal "Verification email sent.", result[:message]
              assert_equal @sa.id, result[:sender_address][:id]
            end
          end
        end

        test "verification_triggered is false when IdentityCreator returns ok:false" do
          creator_result = Ses::IdentityCreator::Result.new(
            ok: false, status: "unconfigured", message: "SES not configured."
          )

          with_creator_stub(on_call: ->(_sa) { creator_result }) do
            with_checker_stub(on_call: ->(sa) { sa.update!(verified: false, ses_status: "unconfigured") }) do
              result = Verify.new.invoke(
                arguments: {"id" => @sa.id, "send_verification_email" => true},
                context: @ctx
              )
              assert_equal false, result[:verification_triggered]
              assert_equal "unconfigured", result[:status]
              assert_equal "SES not configured.", result[:message]
            end
          end
        end

        test "raises RecordNotFound for sender address on another team" do
          other_team = create(:team)
          other = other_team.sender_addresses.create!(email: "other@example.com")
          assert_raises(ActiveRecord::RecordNotFound) do
            Verify.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end

        test "defaults send_verification_email to false when omitted (no creator called)" do
          checker_called = false
          with_checker_stub(on_call: ->(sa) {
            checker_called = true
            sa.update!(verified: false, ses_status: "not_in_ses")
          }) do
            result = Verify.new.invoke(arguments: {"id" => @sa.id}, context: @ctx)
            assert checker_called, "IdentityChecker should have been called"
            assert_equal false, result[:verification_triggered]
            assert_equal "not_in_ses", result[:status]
          end
        end
      end
    end
  end
end
