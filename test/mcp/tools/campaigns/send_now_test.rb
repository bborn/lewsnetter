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
            result = SendNow.new.invoke(arguments: {"id" => @campaign.id, "all_subscribers" => true}, context: @ctx)
            assert result[:enqueued]
            assert_equal @campaign.id, result[:campaign_id]
            assert_equal "sending", result[:status_after]
          end
        end

        test "returns subscriber_count" do
          @team.subscribers.create!(email: "a@b.com", external_id: "sub1", subscribed: true)
          result = SendNow.new.invoke(arguments: {"id" => @campaign.id, "all_subscribers" => true}, context: @ctx)
          assert_equal 1, result[:subscriber_count]
        end

        test "refuses to send an already-sent campaign" do
          @campaign.update!(status: "sent")
          result = SendNow.new.invoke(arguments: {"id" => @campaign.id, "all_subscribers" => true}, context: @ctx)
          refute result[:enqueued]
          assert_equal "sent", result[:status_after]
          assert result[:error].include?("sent")
        end

        test "refuses to send a failed campaign" do
          @campaign.update!(status: "failed")
          result = SendNow.new.invoke(arguments: {"id" => @campaign.id, "all_subscribers" => true}, context: @ctx)
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

        test "refuses a campaign with no segment unless all_subscribers is true" do
          assert_no_enqueued_jobs(only: SendCampaignJob) do
            error = assert_raises(Mcp::Tool::ArgumentError) do
              SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
            end
            assert_match(/no segment/, error.message)
          end
        end

        test "sends a campaign with a segment without all_subscribers" do
          segment = @team.segments.create!(name: "Everyone", predicate: "subscribers.subscribed = 1")
          @campaign.update!(segment: segment)
          assert_enqueued_with(job: SendCampaignJob) do
            assert SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)[:enqueued]
          end
        end

        def with_stub_ses
          original = Rails.application.config.ses_client
          Rails.application.config.ses_client = :stub
          yield
        ensure
          Rails.application.config.ses_client = original
        end

        test "a queued send skips when the segment is removed before the job runs" do
          @team.subscribers.create!(email: "a@example.com", external_id: "sn-a", subscribed: true)
          @team.subscribers.create!(email: "b@example.com", external_id: "sn-b", subscribed: true)
          segment = @team.segments.create!(name: "Only A", definition: {"predicate" => "external_id = 'sn-a'"})
          @campaign.update!(segment: segment)

          assert SendNow.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)[:enqueued]
          @campaign.update!(segment: nil)
          with_stub_ses { perform_enqueued_jobs }

          assert_equal 0, @campaign.deliveries.count
          assert_equal "draft", @campaign.reload.status
        end

        test "an all_subscribers send is recorded, so the queued job sends to everyone" do
          @team.subscribers.create!(email: "a@example.com", external_id: "sn-a", subscribed: true)
          @team.subscribers.create!(email: "b@example.com", external_id: "sn-b", subscribed: true)

          SendNow.new.invoke(arguments: {"id" => @campaign.id, "all_subscribers" => true}, context: @ctx)
          assert @campaign.reload.all_subscribers_confirmed?
          with_stub_ses { perform_enqueued_jobs }

          assert_equal "sent", @campaign.reload.status
          assert_equal 2, @campaign.deliveries.count
        end
      end
    end
  end
end
