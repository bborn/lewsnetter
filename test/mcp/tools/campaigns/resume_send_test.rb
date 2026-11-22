# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class ResumeSendTest < ActiveSupport::TestCase
        include ActiveJob::TestHelper

        def queue_adapter_for_test
          ActiveJob::QueueAdapters::TestAdapter.new
        end

        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(subject: "Resume Me", status: "draft", body_markdown: "Hello", all_subscribers_confirmed: true)
          a = @team.subscribers.create!(email: "a@example.com", external_id: "r-a", subscribed: true)
          @team.subscribers.create!(email: "b@example.com", external_id: "r-b", subscribed: true)
          @campaign.update!(status: "sending")
          @campaign.deliveries.create!(subscriber: a, status: "sent", ses_message_id: "first-run", sent_at: 1.hour.ago)
          @campaign.update!(status: "failed")
        end

        test "enqueues a resume for a failed campaign and reports who is left" do
          assert_enqueued_with(job: SendCampaignJob, args: [@campaign.id, {resume: true}]) do
            result = ResumeSend.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
            assert result[:enqueued]
            assert_equal 1, result[:remaining_count]
          end
        end

        test "refuses a campaign that is neither failed nor stuck" do
          @campaign.update_columns(status: "sent")
          result = ResumeSend.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          refute result[:enqueued]
          assert_match(/can be resumed/, result[:error])
          assert_no_enqueued_jobs(only: SendCampaignJob)
        end

        test "raises RecordNotFound for a campaign on another team" do
          other = create(:team).campaigns.create!(subject: "Other", status: "failed", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            ResumeSend.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end

        test "resumes a confirmed all-subscribers send and mails who is left" do
          original = Rails.application.config.ses_client
          Rails.application.config.ses_client = :stub
          begin
            assert ResumeSend.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)[:enqueued]
            perform_enqueued_jobs
          ensure
            Rails.application.config.ses_client = original
          end

          assert_equal "sent", @campaign.reload.status
          assert_equal 2, @campaign.deliveries.count
        end

        test "a segment-less send that was never confirmed needs all_subscribers to resume" do
          @campaign.update_columns(all_subscribers_confirmed: false)
          tool = ResumeSend.new

          error = assert_raises(Mcp::Tool::ArgumentError) do
            tool.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          end
          assert_match(/no segment/, error.message)
          assert_no_enqueued_jobs(only: SendCampaignJob)

          assert tool.invoke(arguments: {"id" => @campaign.id, "all_subscribers" => true}, context: @ctx)[:enqueued]
          assert @campaign.reload.all_subscribers_confirmed?
        end
      end
    end
  end
end
