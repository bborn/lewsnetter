# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tool
    class AbilitiesTest < ActiveSupport::TestCase
      setup do
        @admin = create(:onboarded_user)
        @team = @admin.current_team
        @member = create(:onboarded_user)
        @membership = create(:membership, team: @team, user: @member) # default role: read-only
        @subscriber = @team.subscribers.create!(email: "reader@example.com", subscribed: true)
      end

      def agent_tool(user, name, team: @team)
        ctx = Context.new(user: user, team: team)
        Chats::ToolAdapter.adapt_all(context: ctx).map(&:new).find { |t| t.name == name }
      end

      test "every tool declares an ability CanCan can check" do
        files = Dir.glob(Rails.root.join("app/mcp/tools/**/*.rb")).reject { |f| f.end_with?("serializers.rb") }
        tools = Loader.load_all.select { |k| k.name.to_s.start_with?("Mcp::Tools::") }

        assert_equal files.size, tools.size
        tools.each do |tool|
          action, model = tool.requires_ability
          assert_kind_of Symbol, action, "#{tool.tool_name} declares no ability"
          assert model.is_a?(Class) && model <= ApplicationRecord, "#{tool.tool_name} needs a model, got #{model.inspect}"
        end
      end

      test "a tool without a declared ability is refused" do
        bare = Class.new(Base) { tool_name "bare_tool" }
        Base.descendants.delete(bare)

        assert_raises(CanCan::AccessDenied) { bare.new.invoke(arguments: {}, context: Context.new(user: @admin, team: @team)) }
      end

      test "a read-only member can read but not write through the agent" do
        assert_equal 1, agent_tool(@member, "subscribers_list").execute[:total]

        result = agent_tool(@member, "subscribers_delete").execute(id: @subscriber.id)

        assert_equal({error: Base::NOT_ALLOWED}, result)
        assert Subscriber.exists?(@subscriber.id)
      end

      test "a read-only member cannot reach sequences, which are admin-only over HTTP too" do
        assert_equal({error: Base::NOT_ALLOWED}, agent_tool(@member, "sequences_list").execute)
        assert_not_includes agent_tool(@admin, "sequences_list").execute.keys, :error
      end

      test "an admin can write through the agent" do
        result = agent_tool(@admin, "subscribers_delete").execute(id: @subscriber.id)

        assert_equal true, result[:deleted]
        assert_not Subscriber.exists?(@subscriber.id)
      end

      test "a role change applies to a context that is already open" do
        @membership.update!(role_ids: [Role.admin.id])
        tool = agent_tool(@member, "subscribers_delete")
        Ability.new(@member) # warms the role caches on the context's user object
        Membership.find(@membership.id).update!(role_ids: [])

        assert_equal({error: Base::NOT_ALLOWED}, tool.execute(id: @subscriber.id))
        assert Subscriber.exists?(@subscriber.id)
      end

      test "being an admin of another team grants nothing here" do
        other_team = create(:team)
        create(:membership, team: other_team, user: @member, role_ids: [Role.admin.id])

        assert_equal({error: Base::NOT_ALLOWED}, agent_tool(@member, "subscribers_delete").execute(id: @subscriber.id))
      end
    end
  end
end
