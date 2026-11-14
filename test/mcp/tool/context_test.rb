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

      test "may_call? limits only tokens granted mcp:read without a write scope" do
        user = create(:onboarded_user)
        reader = Class.new { def self.read_only? = true }
        writer = Class.new { def self.read_only? = false }
        expectations = {
          nil => true, # the in-app agent has no token
          [] => true,
          %w[read write delete] => true,
          %w[admin] => true,
          %w[mcp:write] => true,
          %w[mcp:read mcp:write] => true,
          %w[admin mcp:read] => true,
          %w[mcp:read] => false
        }

        expectations.each do |scopes, may_write|
          ctx = Context.new(user: user, team: user.current_team, scopes: scopes)
          assert ctx.may_call?(reader), "#{scopes.inspect} must read"
          assert_equal may_write, ctx.may_call?(writer), "#{scopes.inspect} write access"
        end
      end

      test "raises if user or team is nil" do
        assert_raises(ArgumentError) { Context.new(user: nil, team: create(:team)) }
        assert_raises(ArgumentError) { Context.new(user: create(:onboarded_user), team: nil) }
      end
    end
  end
end
