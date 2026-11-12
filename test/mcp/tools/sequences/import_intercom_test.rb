# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Sequences
      # Runs the real importer on the trimmed 381681 export fixture (two
      # emails); only the MCP boundary is new here.
      class ImportIntercomTest < ActiveSupport::TestCase
        EXPORT = Rails.root.join("test/fixtures/files/intercom_series/381681.json")

        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @sender = @team.sender_addresses.create!(email: "hello@example.com", name: "Hello",
            verified: true, ses_status: "verified")
          @template = @team.email_templates.create!(name: "Ported", mjml_body: "<mjml><mj-body></mj-body></mjml>")
          @other_team = create(:team)
          @export = JSON.parse(EXPORT.read)
          # Matches the trigger segment, so an accidental activation/enrollment would catch it.
          @team.subscribers.create!(email: "new@example.com", subscribed: true,
            custom_attributes: {"tokens_count" => 0})
        end

        test "a dry run reports what it would create and writes nothing" do
          result = nil
          assert_no_difference ["Sequence.count", "SequenceStep.count", "Segment.count", "Campaign.count"] do
            result = invoke(dry_run: nil) # dry_run defaults to true
          end

          assert result[:dry_run]
          row = result[:results].sole
          assert_equal "would_create", row[:status]
          assert_equal "Connect accounts", row[:name]
          assert_equal 381681, row[:intercom_id]
          assert_equal 2, row[:steps]
          assert_nil row[:sequence_id]
          assert_equal ["Never connected", "Connected"], row[:segments]
          assert_equal ["Never connected", "Connected"], result[:segments_to_create]
          assert_includes row[:warnings], "43879339: A/B variant dropped (kept version A)"
          assert_equal ["posts dropped"], row[:changes]
        end

        test "a dry run needs no template but checks one that is given" do
          assert_equal "would_create", invoke(email_template_id: nil)[:results].sole[:status]
          assert_raises(ActiveRecord::RecordNotFound) do
            invoke(email_template_id: @other_team.email_templates.create!(name: "x", mjml_body: "<mjml/>").id)
          end
        end

        test "a real run creates a draft sequence with steps on the calling team only" do
          assert_no_difference ["@other_team.sequences.count", "@other_team.segments.count", "SequenceEnrollment.count"] do
            assert_difference -> { @team.sequences.count } => 1, -> { SequenceStep.count } => 2 do
              @result = invoke(dry_run: false)
            end
          end

          row = @result[:results].sole
          assert_equal "created", row[:status]
          assert_equal "draft", row[:sequence_status]
          assert_equal ["Never connected", "Connected"], @result[:segments_created]

          sequence = @team.sequences.find_by!(id: row[:sequence_id])
          assert sequence.draft?
          assert_equal "Connect accounts", sequence.name
          assert_equal "Never connected", sequence.trigger_segment.name
          assert_equal @team, sequence.trigger_segment.team
          assert_equal @sender, sequence.sender_address
          assert_equal [@template, @template], sequence.steps.map(&:email_template)
          assert_equal "[Action Needed] Connect Your Accounts💥", sequence.steps.first.subject
          assert_equal 8 * 1440 + 12 * 60, sequence.steps.second.delay_minutes
          assert_empty sequence.enrollments
          refute @team.reload.sequences_enabled?, "never flips the team's Sequences flag"
          refute @result[:sequences_enabled]
        end

        test "re-running skips the existing sequence" do
          invoke(dry_run: false)
          assert_no_difference ["Sequence.count", "SequenceStep.count", "Segment.count"] do
            row = invoke(dry_run: false)[:results].sole
            assert_equal "skipped", row[:status]
            assert_equal "draft", row[:sequence_status]
          end
          assert_equal "skipped", invoke[:results].sole[:status], "dry run reports the skip too"
        end

        test "leaves an existing sequence of the same name untouched, active or not" do
          live = @team.sequences.create!(name: "Connect accounts", trigger_type: "event",
            trigger_event_name: "x", status: "active", sender_address: @sender)
          row = invoke(dry_run: false)[:results].sole
          assert_equal ["skipped", live.id, "active"], row.values_at(:status, :sequence_id, :sequence_status)
          assert_empty live.reload.steps
        end

        test "rejects another team's sender address or email template" do
          other_sender = @other_team.sender_addresses.create!(email: "x@example.com")
          other_template = @other_team.email_templates.create!(name: "x", mjml_body: "<mjml/>")
          assert_no_difference ["Sequence.count", "Segment.count"] do
            assert_raises(ActiveRecord::RecordNotFound) { invoke(dry_run: false, sender_address_id: other_sender.id) }
            assert_raises(ActiveRecord::RecordNotFound) { invoke(dry_run: false, email_template_id: other_template.id) }
          end
        end

        test "a real run refuses without an email template" do
          error = assert_raises(Mcp::Tool::ArgumentError) { invoke(dry_run: false, email_template_id: nil) }
          assert_match(/email template is required/, error.message)
          assert_equal 0, @team.sequences.count
        end

        test "accepts the export as a JSON string, the full spec as YAML and symbol keys from the transport" do
          full = full_spec
          full["series"] << {"intercom_id" => 378582, "name" => "Re-engage dormant", "steps" => []}
          row = invoke(dry_run: false, series_json: @export.to_json, spec: full.to_yaml, segments: nil)[:results].sole
          assert_equal "created", row[:status]

          symbolized = invoke(dry_run: true, series_json: @export.deep_symbolize_keys,
            spec: entry.deep_symbolize_keys, segments: segments.deep_symbolize_keys)
          assert_equal "skipped", symbolized[:results].sole[:status]
        end

        test "an exclude names a series imported by an earlier call, or warns" do
          dormant = @team.sequences.create!(name: "Re-engage dormant", trigger_type: "event", trigger_event_name: "x")
          full = full_spec
          full["series"].first["exclude"] = [378582, 375135, 999]
          full["series"] << {"intercom_id" => 378582, "name" => "Re-engage dormant"}
          full["series"] << {"intercom_id" => 375135, "name" => "Brand invited"}

          row = invoke(dry_run: false, spec: full, segments: nil)[:results].sole
          assert_equal ["Re-engage dormant"], row[:excluded_sequences]
          assert_equal [dormant.id], @team.sequences.find_by!(id: row[:sequence_id]).excluded_sequence_ids
          assert_includes row[:warnings],
            "excluded series 375135 (Brand invited) isn't imported yet: rule dropped; import it first"
          assert_includes row[:warnings], "excluded series 999 isn't ported: rule dropped"
          assert_equal 0, @team.sequences.where(name: "Brand invited").count, "only the export's series is imported"
        end

        test "a spec without this export's series is an argument error" do
          bad = entry.merge("intercom_id" => 1)
          assert_raises(Mcp::Tool::ArgumentError) { invoke(spec: bad) }
          assert_raises(Mcp::Tool::ArgumentError) { invoke(series_json: "{not json: [") }
        end

        private

        def invoke(**overrides)
          args = {
            "series_json" => @export,
            "spec" => entry,
            "segments" => segments,
            "sender_address_id" => @sender.id,
            "email_template_id" => @template.id
          }.merge(overrides.transform_keys(&:to_s)).compact
          ImportIntercom.new.invoke(arguments: args, context: @ctx)
        end

        def full_spec
          {"segments" => segments, "series" => [entry]}
        end

        def segments
          {
            "Never connected" => {"predicate" => "COALESCE(json_extract(subscribers.custom_attributes, '$.tokens_count'), 0) = 0"},
            "Connected" => {"rules" => {"type" => "group", "combinator" => "and", "rules" => [
              {"type" => "rule", "field" => "subscribers.tags", "operator" => "contains", "value" => "Connected"}
            ]}},
            "Unused" => {"predicate" => "1 = 1"}
          }
        end

        def entry
          {
            "intercom_id" => 381681,
            "name" => "Connect accounts",
            "trigger" => {"segment" => "Never connected"},
            "goal" => {"event" => "account:connected"},
            "exit_segment" => "Connected",
            "finish_after_days" => 3,
            "steps" => [
              {"email" => "43856798", "action" => {"on" => "goal", "tag" => "Connected", "exit" => true}},
              {"email" => "43879339", "wait_days" => 8, "wait_hours" => 12, "skip_segment" => "Connected"}
            ],
            "changes" => ["posts dropped"]
          }
        end
      end
    end
  end
end
