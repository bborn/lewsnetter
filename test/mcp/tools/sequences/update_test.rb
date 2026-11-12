# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Sequences
      class UpdateTest < ActiveSupport::TestCase
        setup do
          @tool = Update.new # loads Mcp::Tool::Base, which defines Mcp::Tool::ArgumentError
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          sender = create(:sender_address, team: @team, verified: true, ses_status: "verified")
          @sequence = create(:sequence, team: @team, name: "New paying brand", sender_address: sender)
          create(:sequence_step, sequence: @sequence)
          @segment = create(:segment, team: @team, name: "Not a brand")
        end

        test "sets the exit segment and status" do
          result = @tool.invoke(arguments: {"id" => @sequence.id, "exit_segment_id" => @segment.id,
                                            "status" => "active"}, context: @ctx)
          @sequence.reload
          assert_equal @segment.id, @sequence.exit_segment_id
          assert_equal "active", @sequence.status
          assert_equal @segment.id, result[:sequence][:exit_segment_id]
          assert_equal "active", result[:sequence][:status]
        end

        test "a sequence without a sender cannot go active" do
          bare = create(:sequence, team: @team, name: "No sender")
          error = assert_raises(Mcp::Tool::ArgumentError) do
            @tool.invoke(arguments: {"id" => bare.id, "status" => "active"}, context: @ctx)
          end
          assert_match(/Sender address/, error.message)
          assert_equal "draft", bare.reload.status
        end

        test "null clears the exit segment" do
          @sequence.update!(exit_segment: @segment)
          @tool.invoke(arguments: {"id" => @sequence.id, "exit_segment_id" => nil}, context: @ctx)
          assert_nil @sequence.reload.exit_segment_id
        end

        test "refuses another team's segment" do
          other = create(:segment, name: "Elsewhere")
          assert_raises(Mcp::Tool::ArgumentError) do
            @tool.invoke(arguments: {"id" => @sequence.id, "exit_segment_id" => other.id}, context: @ctx)
          end
          assert_nil @sequence.reload.exit_segment_id
        end

        test "cannot reach another team's sequence" do
          other = create(:sequence, name: "Other team")
          assert_raises(ActiveRecord::RecordNotFound) do
            @tool.invoke(arguments: {"id" => other.id, "status" => "active"}, context: @ctx)
          end
          assert_equal "draft", other.reload.status
        end
      end
    end
  end
end
