# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module EmailTemplates
      class DeleteTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @template = @team.email_templates.create!(name: "Deletable Template", mjml_body: "<mjml></mjml>")
        end

        test "deletes template and returns deleted:true with id" do
          id = @template.id
          result = Delete.new.invoke(arguments: {"id" => id}, context: @ctx)
          assert_equal true, result[:deleted]
          assert_equal id, result[:id]
          refute @team.email_templates.exists?(id)
        end

        test "raises RecordNotFound for template on another team" do
          other_team = create(:team)
          other_template = other_team.email_templates.create!(name: "Other", mjml_body: "<mjml></mjml>")
          assert_raises(ActiveRecord::RecordNotFound) do
            Delete.new.invoke(arguments: {"id" => other_template.id}, context: @ctx)
          end
        end

        test "campaigns referencing the deleted template have email_template_id nullified (dependent: :nullify)" do
          campaign = @team.campaigns.create!(
            subject: "Test Campaign",
            status: "draft",
            email_template: @template,
            body_markdown: "Hello world"
          )
          Delete.new.invoke(arguments: {"id" => @template.id}, context: @ctx)
          assert_nil campaign.reload.email_template_id
          refute @team.email_templates.exists?(@template.id)
        end
      end
    end
  end
end
