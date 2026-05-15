# frozen_string_literal: true

require "test_helper"

module Agent
  class ToolAdapterTest < ActiveSupport::TestCase
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
    end

    test "adapts an Mcp::Tool::Base class into a RubyLLM::Tool subclass" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Team::GetCurrent, context: @ctx)
      assert adapted < RubyLLM::Tool
    end

    test "adapted tool's instance #name returns our tool's snake_case name" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Team::GetCurrent, context: @ctx)
      assert_equal "team_get_current", adapted.new.name
    end

    test "adapted tool's #execute calls our tool's #invoke with context" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Team::GetCurrent, context: @ctx)
      result = adapted.new.execute({})
      assert_equal @team.id, result[:id]
    end

    test "adapt_all returns one wrapper class per loaded tool" do
      adapted = ToolAdapter.adapt_all(context: @ctx)
      assert adapted.is_a?(Array)
      assert(adapted.all? { |c| c < RubyLLM::Tool })
      assert_equal Mcp::Tool::Loader.load_all.size, adapted.size
    end
  end
end
