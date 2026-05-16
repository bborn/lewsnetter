# frozen_string_literal: true

require "test_helper"

module Mcp
  module Skill
    class RegistrationIntegrationTest < ActionDispatch::IntegrationTest
      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
        @team.update!(slug: "test-team-slug") unless @team.slug?
        @platform_application = create(:platform_application, team: @team)
        @token = Doorkeeper::AccessToken.create!(
          resource_owner_id: @user.id,
          application: @platform_application,
          scopes: "read write delete",
          token: SecureRandom.hex
        )
      end

      def post_mcp(body)
        post "/mcp/messages",
          params: body.to_json,
          headers: {
            "Authorization" => "Bearer #{@token.token}",
            "Content-Type" => "application/json"
          }
      end

      test "resources/list returns all 6 skills" do
        post_mcp(jsonrpc: "2.0", id: 10, method: "resources/list")
        assert_response :success

        payload = JSON.parse(response.body)
        assert_equal "2.0", payload["jsonrpc"]
        assert_equal 10, payload["id"]

        resources = payload.dig("result", "resources")
        refute_nil resources, "Expected result.resources in #{payload.inspect}"
        assert_equal 5, resources.length, "Expected 5 skills, got #{resources.length}: #{resources.map { |r| r["uri"] }.inspect}"

        uris = resources.map { |r| r["uri"] }
        assert_includes uris, "skill://analyze-recent-send"
        assert_includes uris, "skill://draft-and-send-newsletter"
        assert_includes uris, "skill://import-subscribers-from-csv"
        assert_includes uris, "skill://segment-cookbook"
        # translate-question-to-segment was retired when the visual segment
        # builder shipped — agents that want to build a segment can call the
        # raw segments_* MCP tools directly + use segment-cookbook for predicate
        # idioms.
        assert_includes uris, "skill://voice-samples"

        # Each entry has the expected shape
        resources.each do |r|
          assert r["uri"].start_with?("skill://"), "URI should start with skill://: #{r["uri"]}"
          assert r["name"].present?, "name should be present: #{r.inspect}"
          assert_equal "text/markdown", r["mimeType"], "mimeType should be text/markdown: #{r.inspect}"
        end
      end

      test "resources/read with skill URI returns markdown content" do
        post_mcp(jsonrpc: "2.0", id: 11, method: "resources/read", params: {
          uri: "skill://draft-and-send-newsletter"
        })
        assert_response :success

        payload = JSON.parse(response.body)
        assert_equal "2.0", payload["jsonrpc"]
        assert_equal 11, payload["id"]

        contents = payload.dig("result", "contents")
        refute_nil contents, "Expected result.contents in #{payload.inspect}"
        assert_equal 1, contents.length

        entry = contents.first
        assert_equal "skill://draft-and-send-newsletter", entry["uri"]
        assert_equal "text/markdown", entry["mimeType"]
        assert entry["text"].present?, "text should be non-empty"
        assert_includes entry["text"], "#", "Expected markdown content in text"
      end

      test "resources/read with unknown skill URI returns error" do
        post_mcp(jsonrpc: "2.0", id: 12, method: "resources/read", params: {
          uri: "skill://nonexistent-skill"
        })
        assert_response :success

        payload = JSON.parse(response.body)
        assert payload["error"].present?, "Expected an error for unknown skill URI: #{payload.inspect}"
      end
    end
  end
end
