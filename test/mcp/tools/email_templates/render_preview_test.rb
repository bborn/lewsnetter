# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module EmailTemplates
      class RenderPreviewTest < ActiveSupport::TestCase
        # A minimal valid MJML template with a {{body}} placeholder so the
        # markdown-path renderer can inject the sample body content.
        PREVIEW_MJML = <<~MJML.freeze
          <mjml>
            <mj-body>
              <mj-section>
                <mj-column>
                  <mj-text>HEADER: {{plan}}</mj-text>
                </mj-column>
              </mj-section>
              {{body}}
            </mj-body>
          </mjml>
        MJML

        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @template = @team.email_templates.create!(
            name: "Preview Template",
            mjml_body: PREVIEW_MJML
          )
        end

        test "happy path: renders HTML for a valid template with no subscriber" do
          result = RenderPreview.new.invoke(
            arguments: {"id" => @template.id},
            context: @ctx
          )
          assert_empty result[:errors]
          assert_kind_of String, result[:html]
          assert result[:html].length > 0
          assert_kind_of Integer, result[:byte_size]
          assert result[:byte_size] > 0
          # Premailer inlines CSS — style attributes should be present
          assert_match(/style=/, result[:html])
        end

        test "other team's template is not accessible (raises RecordNotFound)" do
          other_team = create(:team)
          other_template = other_team.email_templates.create!(
            name: "Other Template",
            mjml_body: PREVIEW_MJML
          )
          assert_raises(ActiveRecord::RecordNotFound) do
            RenderPreview.new.invoke(
              arguments: {"id" => other_template.id},
              context: @ctx
            )
          end
        end

        test "render errors are captured in errors array, not raised" do
          # A template that is structurally invalid MJML — completely non-XML
          # content with no mj-body tag. We temporarily enable
          # Mjml.raise_render_exception (normally only on in development) so the
          # MJML parse failure bubbles up for the tool to catch.
          broken_template = @team.email_templates.create!(
            name: "Broken Template",
            mjml_body: "TOTALLY_INVALID_NOT_MJML_OR_XML"
          )
          original = Mjml.raise_render_exception
          Mjml.raise_render_exception = true
          begin
            result = RenderPreview.new.invoke(
              arguments: {"id" => broken_template.id},
              context: @ctx
            )
            assert_not_empty result[:errors]
            assert_nil result[:html]
          ensure
            Mjml.raise_render_exception = original
          end
        end

        test "subscriber_id path: substitutes subscriber custom_attributes into the template" do
          subscriber = @team.subscribers.create!(
            email: "test@example.com",
            name: "Test User",
            subscribed: true,
            custom_attributes: {"plan" => "enterprise"}
          )
          result = RenderPreview.new.invoke(
            arguments: {"id" => @template.id, "subscriber_id" => subscriber.id},
            context: @ctx
          )
          assert_empty result[:errors]
          assert_kind_of String, result[:html]
          # The template has {{plan}} in the header — should be substituted with "enterprise"
          assert_includes result[:html], "enterprise"
          refute_includes result[:html], "{{plan}}"
        end

        test "sample_data path: substitutes provided hash values into the template" do
          result = RenderPreview.new.invoke(
            arguments: {"id" => @template.id, "sample_data" => {"plan" => "starter"}},
            context: @ctx
          )
          assert_empty result[:errors]
          assert_kind_of String, result[:html]
          assert_includes result[:html], "starter"
          refute_includes result[:html], "{{plan}}"
        end

        test "subscriber_id from another team is not accessible (raises RecordNotFound)" do
          other_team = create(:team)
          other_subscriber = other_team.subscribers.create!(
            email: "other@example.com",
            subscribed: true
          )
          assert_raises(ActiveRecord::RecordNotFound) do
            RenderPreview.new.invoke(
              arguments: {"id" => @template.id, "subscriber_id" => other_subscriber.id},
              context: @ctx
            )
          end
        end
      end
    end
  end
end
