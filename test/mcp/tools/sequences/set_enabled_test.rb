# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Sequences
      class SetEnabledTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          create(:sequence, team: @team)
        end

        test "turns the flag on and off without activating any sequence" do
          result = SetEnabled.new.invoke(arguments: {"enabled" => true}, context: @ctx)
          assert @team.reload.sequences_enabled?
          assert result[:sequences_enabled]
          assert_equal 0, result[:active_sequences]
          assert_equal ["draft"], @team.sequences.pluck(:status).uniq

          SetEnabled.new.invoke(arguments: {"enabled" => false}, context: @ctx)
          refute @team.reload.sequences_enabled?
        end
      end
    end
  end
end
