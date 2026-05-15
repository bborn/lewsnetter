# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Team
      class GetCurrentTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @team.update!(slug: "test-team-slug") unless @team.slug?
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "returns id, name, and slug for the context's team" do
          result = GetCurrent.new.invoke(arguments: {}, context: @ctx)
          assert_equal @team.id, result[:id]
          assert_equal @team.name, result[:name]
          assert_equal @team.slug, result[:slug]
        end

        test "metadata is wired" do
          assert_equal "team.get_current", GetCurrent.tool_name
          assert_match(/team/i, GetCurrent.description)
        end
      end
    end
  end
end
