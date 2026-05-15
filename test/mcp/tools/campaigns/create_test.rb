# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Campaigns
      class CreateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "creates a draft campaign with body_markdown" do
          result = Create.new.invoke(
            arguments: {"subject" => "My Newsletter", "body_markdown" => "## Hello\n\nWorld"},
            context: @ctx
          )
          assert_equal "My Newsletter", result[:campaign][:subject]
          assert_equal "draft", result[:campaign][:status]
          assert @team.campaigns.exists?(result[:campaign][:id])
        end

        test "persists optional fields" do
          result = Create.new.invoke(
            arguments: {
              "subject" => "Test",
              "body_markdown" => "body",
              "preheader" => "Read this"
            },
            context: @ctx
          )
          assert_equal "Read this", result[:campaign][:preheader]
        end

        test "raises RecordInvalid when subject is missing (schema guard)" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Create.new.invoke(arguments: {"body_markdown" => "body"}, context: @ctx)
          end
        end

        test "raises RecordInvalid when no body source is provided" do
          assert_raises(ActiveRecord::RecordInvalid) do
            Create.new.invoke(arguments: {"subject" => "No body"}, context: @ctx)
          end
        end

        test "campaign is scoped to the calling team" do
          result = Create.new.invoke(
            arguments: {"subject" => "Scoped", "body_markdown" => "text"},
            context: @ctx
          )
          campaign = Campaign.find(result[:campaign][:id])
          assert_equal @team.id, campaign.team_id
        end
      end
    end
  end
end
