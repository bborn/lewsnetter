# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module EmailTemplates
      class ListTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)
          @t1 = @team.email_templates.create!(name: "Template One", mjml_body: "<mjml></mjml>")
          @t2 = @team.email_templates.create!(name: "Template Two", mjml_body: "<mjml></mjml>")
          @other = @other_team.email_templates.create!(name: "Other Team Template", mjml_body: "<mjml></mjml>")
        end

        test "lists the team's templates with correct total" do
          result = List.new.invoke(arguments: {"limit" => 50}, context: @ctx)
          ids = result[:email_templates].map { |h| h[:id] }
          assert_includes ids, @t1.id
          assert_includes ids, @t2.id
          refute_includes ids, @other.id
          assert_equal 2, result[:total]
          assert_equal 50, result[:limit]
          assert_equal 0, result[:offset]
        end

        test "other team's templates are not visible" do
          result = List.new.invoke(arguments: {}, context: @ctx)
          ids = result[:email_templates].map { |h| h[:id] }
          refute_includes ids, @other.id
        end

        test "pagination via limit and offset" do
          result = List.new.invoke(arguments: {"limit" => 1, "offset" => 1}, context: @ctx)
          assert_equal 1, result[:email_templates].length
          assert_equal 2, result[:total]
          assert_equal 1, result[:limit]
          assert_equal 1, result[:offset]
        end
      end
    end
  end
end
