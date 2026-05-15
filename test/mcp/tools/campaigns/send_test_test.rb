# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class SendTestTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "My Campaign", status: "draft", body_markdown: "Hello")
        end

        # Helper: temporarily replace SesSender.send_bulk with a block that returns fake_result.
        def with_ses_stub(fake_result, &block)
          SesSender.singleton_class.class_eval do
            alias_method :_orig_send_bulk, :send_bulk
            define_method(:send_bulk) { |**_| fake_result }
          end
          block.call
        ensure
          SesSender.singleton_class.class_eval do
            alias_method :send_bulk, :_orig_send_bulk
            remove_method :_orig_send_bulk
          end
        end

        test "sends to recipient_email via SesSender" do
          fake_result = Struct.new(:failed, :message_ids).new([], ["mock-msg-1"])
          with_ses_stub(fake_result) do
            result = SendTest.new.invoke(
              arguments: {"id" => @campaign.id, "recipient_email" => "x@y.com"},
              context: @ctx
            )
            assert result[:sent]
            assert_equal "x@y.com", result[:recipient_email]
            assert_equal ["mock-msg-1"], result[:message_ids]
            assert_empty result[:errors]
          end
        end

        test "defaults recipient_email to context.user.email" do
          fake_result = Struct.new(:failed, :message_ids).new([], ["mock-id"])
          with_ses_stub(fake_result) do
            result = SendTest.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
            assert_equal @user.email, result[:recipient_email]
          end
        end

        test "does not persist [TEST] prefix to campaign subject" do
          fake_result = Struct.new(:failed, :message_ids).new([], ["mock-id"])
          with_ses_stub(fake_result) do
            SendTest.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          end
          assert_equal "My Campaign", @campaign.reload.subject
        end

        test "returns sent:false and errors when SesSender fails" do
          error_entry = {subscriber: nil, error: "render_failed: bad mjml"}
          fake_result = Struct.new(:failed, :message_ids).new([error_entry], [])
          with_ses_stub(fake_result) do
            result = SendTest.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
            refute result[:sent]
            assert_equal ["bad mjml"], result[:errors]
          end
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            SendTest.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end
      end
    end
  end
end
