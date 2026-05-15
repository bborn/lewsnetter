# frozen_string_literal: true

require "test_helper"

module Mcp
  module Skill
    class RendererTest < ActiveSupport::TestCase
      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
        @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
      end

      def make_skill(body)
        Base.parse(<<~MD)
          ---
          name: test
          description: x
          when_to_use: x
          ---

          #{body}
        MD
      end

      test "renders plain markdown unchanged" do
        skill = make_skill("Hello world")
        assert_equal "Hello world\n", Renderer.new(skill: skill, context: @ctx).call
      end

      test "renders ERB with access to context.team" do
        skill = make_skill("Team is <%= context.team.name %>.")
        assert_includes Renderer.new(skill: skill, context: @ctx).call, "Team is #{@team.name}."
      end

      test "renders ERB with access to context.user" do
        skill = make_skill("User: <%= context.user.email %>")
        assert_includes Renderer.new(skill: skill, context: @ctx).call, "User: #{@user.email}"
      end

      test "rescues ERB errors and returns a clear inline error block" do
        skill = make_skill("<%= raise 'boom' %>")
        out = Renderer.new(skill: skill, context: @ctx).call
        assert_match(/skill render error/i, out)
        assert_match(/boom/, out)
      end
    end
  end
end
