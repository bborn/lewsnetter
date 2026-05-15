# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module EmailTemplates
      class CreateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "creates a new email template and returns it" do
          result = Create.new.invoke(
            arguments: {"name" => "Newsletter Layout", "mjml_body" => "<mjml><mj-body></mj-body></mjml>"},
            context: @ctx
          )
          assert_equal "Newsletter Layout", result[:email_template][:name]
          assert_equal "<mjml><mj-body></mj-body></mjml>", result[:email_template][:mjml_body]
          assert result[:email_template][:id]
          assert @team.email_templates.exists?(name: "Newsletter Layout")
        end

        test "template is scoped to the calling team" do
          other_team = create(:team)
          other_ctx = Mcp::Tool::Context.new(user: create(:onboarded_user), team: other_team)
          Create.new.invoke(
            arguments: {"name" => "Other Team Layout", "mjml_body" => "<mjml></mjml>"},
            context: other_ctx
          )
          refute @team.email_templates.exists?(name: "Other Team Layout")
          assert other_team.email_templates.exists?(name: "Other Team Layout")
        end

        test "raises on missing required name" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Create.new.invoke(arguments: {"mjml_body" => "<mjml></mjml>"}, context: @ctx)
          end
        end

        test "raises on missing required mjml_body" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Create.new.invoke(arguments: {"name" => "No Body"}, context: @ctx)
          end
        end
      end
    end
  end
end
