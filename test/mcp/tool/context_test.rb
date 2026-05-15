# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tool
    class ContextTest < ActiveSupport::TestCase
      test "stores user and team and is frozen" do
        user = create(:onboarded_user)
        team = user.current_team
        ctx = Context.new(user: user, team: team)

        assert_equal user, ctx.user
        assert_equal team, ctx.team
        assert_predicate ctx, :frozen?
      end

      test "raises if user or team is nil" do
        assert_raises(ArgumentError) { Context.new(user: nil, team: create(:team)) }
        assert_raises(ArgumentError) { Context.new(user: create(:onboarded_user), team: nil) }
      end
    end
  end
end
