# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Sequences
      class StatsTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @team.update!(sequences_enabled: true)
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sequence = create(:sequence, :live, team: @team)
          @step1 = create(:sequence_step, sequence: @sequence, subject: "Hello")
          @step2 = create(:sequence_step, sequence: @sequence, delay_minutes: 1440)
        end

        test "returns a per-step funnel from real deliveries and enrollments" do
          a = create(:subscriber, team: @team)
          b = create(:subscriber, team: @team)
          @sequence.enroll!(a).update!(current_step: 1)
          @sequence.enroll!(b).exit!("unsubscribed")
          opened = Delivery.create!(campaign: @step1.campaign, subscriber: a, ses_message_id: "m-a",
            sent_at: 1.hour.ago)
          OpenEvent.record!(delivery: opened, ip: "203.0.113.9", http_method: "GET",
            user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Version/17.5 Safari/605.1.15")
          Delivery.create!(campaign: @step1.campaign, subscriber: b, ses_message_id: "m-b",
            sent_at: Time.current)

          result = Stats.new.invoke(arguments: {"id" => @sequence.id}, context: @ctx)
          assert_equal({"active" => 1, "completed" => 0, "exited" => 1, "suppressed" => 0}, result[:enrollments])
          assert_equal({"unsubscribed" => 1}, result[:exit_reasons])

          first, second = result[:steps]
          assert_equal @step1.id, first[:id]
          assert_equal "Hello", first[:subject]
          assert_equal 1, first[:position]
          assert_equal 2, first[:sent]
          assert_equal 1, first[:opened]
          assert_equal 0, first[:waiting]
          assert_equal 1, second[:waiting]
          assert_equal 0, second[:sent]
          assert_equal 1440, second[:delay_minutes]
        end

        test "another team's sequence is not found" do
          other = create(:sequence)
          assert_raises(ActiveRecord::RecordNotFound) do
            Stats.new.invoke(arguments: {"id" => other.id}, context: @ctx)
          end
        end
      end
    end
  end
end
