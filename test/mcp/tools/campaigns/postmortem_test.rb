# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class PostmortemTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @campaign = @team.campaigns.create!(
            subject: "Sent Campaign",
            status: "sent",
            body_markdown: "Hello",
            sent_at: 1.day.ago
          )
        end

        # Convenience: each delivery needs a unique subscriber + unique
        # ses_message_id, so we mint both fresh per call.
        def make_delivery(**attrs)
          subscriber = @team.subscribers.create!(
            email: "sub-#{SecureRandom.hex(4)}@example.com",
            external_id: "ext-#{SecureRandom.hex(4)}",
            subscribed: true
          )
          Delivery.create!(
            {
              campaign: @campaign,
              subscriber: subscriber,
              ses_message_id: "msg-#{SecureRandom.hex(4)}",
              sent_at: Time.current,
              status: "sent"
            }.merge(attrs)
          )
        end

        test "returns stats hash with all eight counters" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert result.key?(:stats)
          %i[sent delivered opened clicked bounced complained unsubscribed failed].each do |key|
            assert result[:stats].key?(key), "missing key #{key}"
          end
        end

        test "counts sent rows from deliveries with a ses_message_id" do
          3.times { make_delivery }
          make_delivery(ses_message_id: nil, status: "failed", sent_at: nil, error_message: "x")

          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal 3, result[:stats][:sent]
          assert_equal 1, result[:stats][:failed]
        end

        test "counts delivered, bounced, complained from the right timestamp columns" do
          make_delivery(delivered_at: Time.current, status: "delivered")
          make_delivery(delivered_at: Time.current, status: "delivered")
          make_delivery(bounced_at: Time.current, status: "bounced", bounce_subtype: "Permanent")
          make_delivery(complained_at: Time.current, status: "complained")
          # sent-only baseline
          make_delivery

          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal 5, result[:stats][:sent]
          assert_equal 2, result[:stats][:delivered]
          assert_equal 1, result[:stats][:bounced]
          assert_equal 1, result[:stats][:complained]
        end

        test "opened, clicked, unsubscribed are 0 until Phase 2 populates them" do
          3.times { make_delivery }
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal 0, result[:stats][:opened]
          assert_equal 0, result[:stats][:clicked]
          assert_equal 0, result[:stats][:unsubscribed]
        end

        test "campaign with no deliveries returns all zeros" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_equal 0, result[:stats][:sent]
          assert_equal 0, result[:stats][:delivered]
          assert_equal 0, result[:stats][:bounced]
          assert_equal 0, result[:stats][:complained]
          assert_equal 0, result[:stats][:failed]
        end

        test "returns analyzed_at as ISO8601 string" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert_match(/\d{4}-\d{2}-\d{2}T/, result[:analyzed_at])
        end

        test "returns top_links array" do
          result = Postmortem.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
          assert result.key?(:top_links)
          assert result[:top_links].is_a?(Array)
        end

        test "raises RecordNotFound for campaign on another team" do
          other_team = create(:team)
          other = other_team.campaigns.create!(subject: "Other", status: "sent", body_markdown: "body")
          assert_raises(ActiveRecord::RecordNotFound) do
            Postmortem.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end
      end
    end
  end
end
