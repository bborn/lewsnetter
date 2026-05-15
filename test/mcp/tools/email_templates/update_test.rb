# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module EmailTemplates
      class UpdateTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @template = @team.email_templates.create!(name: "Original Name", mjml_body: "<mjml><mj-body></mj-body></mjml>")
        end

        test "updates name and returns updated template" do
          result = Update.new.invoke(
            arguments: {"id" => @template.id, "name" => "Updated Name"},
            context: @ctx
          )
          assert_equal @template.id, result[:email_template][:id]
          assert_equal "Updated Name", result[:email_template][:name]
          assert_equal "Updated Name", @template.reload.name
        end

        test "updates mjml_body only" do
          new_body = "<mjml><mj-body><mj-section></mj-section></mj-body></mjml>"
          result = Update.new.invoke(
            arguments: {"id" => @template.id, "mjml_body" => new_body},
            context: @ctx
          )
          assert_equal new_body, result[:email_template][:mjml_body]
          assert_equal new_body, @template.reload.mjml_body
        end

        test "other team's template is not accessible (raises RecordNotFound)" do
          other_team = create(:team)
          other_template = other_team.email_templates.create!(name: "Other", mjml_body: "<mjml></mjml>")
          assert_raises(ActiveRecord::RecordNotFound) do
            Update.new.invoke(
              arguments: {"id" => other_template.id, "name" => "Hacked"},
              context: @ctx
            )
          end
        end

        test "raises on missing required id" do
          assert_raises(Mcp::Tool::ArgumentError) do
            Update.new.invoke(arguments: {"name" => "No ID"}, context: @ctx)
          end
        end
      end
    end
  end
end
