# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class SendNowTest < ActiveSupport::TestCase
        include ActiveJob::TestHelper

        # Override the inline adapter so assert_enqueued_with works.
        def queue_adapter_for_test
          ActiveJob::QueueAdapters::TestAdapter.new
        end

        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "Send Me", status: "draft", body_markdown: "Hello")
        end

        test "enqueues SendCampaignJob for a sendable campaign" do
          assert_enqueued_with(job: SendCampaignJob) do
            result = SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
            assert result[:enqueued]
            assert_equal @campaign.id, result[:campaign_id]
            assert_equal "sending", result[:status_after]
          end
        end

        test "returns subscriber_count" do
          @team.subscribers.create!(email: "a@b.com", external_id: "sub1", subscribed: true)
          result = SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal 1, result[:subscriber_count]
        end

        test "refuses to send an already-sent campaign" do
          @campaign.update!(status: "sent")
          result = SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          refute result[:enqueued]
          assert_equal "sent", result[:status_after]
          assert result[:error].include?("sent")
        end

        test "refuses to send a failed campaign" do
          @campaign.update!(status: "failed")
          result = SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          refute result[:enqueued]
          assert_equal "failed", result[:status_after]
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "draft", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            SendNow.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end
      end
    end
  end
end
