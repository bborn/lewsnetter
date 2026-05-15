# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module EmailTemplates
      class GetTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @template = @team.email_templates.create!(name: "My Template", mjml_body: "<mjml><mj-body></mj-body></mjml>")
          @other_template = @other_team.email_templates.create!(name: "Other Template", mjml_body: "<mjml></mjml>")
        end

        test "returns email_template data for a valid id" do
          result = Get.new.invoke(arguments: {"id" => @template.id}, context: @ctx)
          assert_equal @template.id, result[:email_template][:id]
          assert_equal "My Template", result[:email_template][:name]
          assert_equal "<mjml><mj-body></mj-body></mjml>", result[:email_template][:mjml_body]
          assert result[:email_template][:created_at]
          assert result[:email_template][:updated_at]
        end

        test "other team's template is not accessible (raises RecordNotFound)" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => @other_template.id}, context: @ctx)
          end
        end

        test "missing id raises RecordNotFound" do
          assert_raises(ActiveRecord::RecordNotFound) do
            Get.new.invoke(arguments: {"id" => 999_999_999}, context: @ctx)
          end
        end
      end
    end
  end
end
