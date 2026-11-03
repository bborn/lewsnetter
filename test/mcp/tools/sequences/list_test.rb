# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Sequences
      class ListTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @team.update!(sequences_enabled: true)
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @live = create(:sequence, :live, team: @team, name: "Welcome")
          create(:sequence_step, sequence: @live)
          create(:sequence_step, sequence: @live, delay_minutes: 60)
          @draft = create(:sequence, team: @team, name: "Draft one")
          @other = create(:sequence, name: "Other team")
          @live.enroll!(create(:subscriber, team: @team))
        end

        test "lists only the calling team's sequences with steps and enrollment counts" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          assert result[:sequences_enabled]
          assert_equal 2, result[:total]
          ids = result[:sequences].map { _1[:id] }
          assert_equal [@live.id, @draft.id], ids
          live = result[:sequences].first
          assert_equal "Welcome", live[:name]
          assert_equal "event", live[:trigger_type]
          assert_equal "signed_up", live[:trigger_event_name]
          assert_equal 2, live[:steps_count]
          assert_equal 1, live[:enrollments]["active"]
          assert_equal 0, live[:enrollments]["completed"]
        end

        test "filters by status" do
          result = List.new.invoke(arguments: {"status" => "draft"}, context: @ctx)
          assert_equal [@draft.id], result[:sequences].map { _1[:id] }
        end
      end
    end
  end
end
