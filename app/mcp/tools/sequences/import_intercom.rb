# frozen_string_literal: true

module Mcp
  module Tools
    module Sequences
      # The MCP door to Sequences::IntercomSeriesImporter, which the
      # `sequences:import_intercom_series` rake task also runs. One series per
      # call keeps the payload small; the spec is the same port spec the rake
      # task reads (or just this series' entry plus the segments it uses).
      #
      # Drafts only: it never activates a sequence, enrolls anyone, sends, or
      # touches the team's sequences_enabled flag. A sequence whose name
      # already exists is skipped.
      class ImportIntercom < Mcp::Tool::Base
        tool_name "sequences_import_intercom"
        description "Ports one Intercom Series export into a DRAFT sequence on the calling team, " \
          "following a port spec. Dry run by default: reports the sequence name, step count, " \
          "segments and warnings without writing; pass dry_run: false to create. Never activates, " \
          "enrolls or sends; a sequence whose name already exists is skipped. `series_json` is " \
          "the series export (object or JSON string, needs `series` and `rulesets`). `spec` is " \
          "the port spec in the rake task's shape ({segments, series: [...]}, e.g. the whole " \
          "port.yml) or a single series entry ({intercom_id, name, trigger, steps, ...}); YAML or " \
          "JSON strings are accepted. With a single entry pass the segment definitions it uses in " \
          "`segments`. Only the entry matching the export's series id is imported; the rest of a " \
          "full spec only names `exclude` references, so import excluded series first. " \
          "email_template_id is required unless dry_run (see email_templates_list and " \
          "sender_addresses_list)."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          required: ["series_json", "spec"],
          properties: {
            series_json: {type: ["object", "string"]},
            spec: {type: ["object", "string"]},
            segments: {type: ["object", "string"]},
            sender_address_id: {type: "integer"},
            email_template_id: {type: "integer"},
            dry_run: {type: "boolean", default: true}
          }
        )

        def call(arguments:, context:)
          export = parse(arguments["series_json"], "series_json")
          intercom_id = export.dig("series", "id")
          raise Mcp::Tool::ArgumentError, "series_json has no series.id" if intercom_id.blank?

          dry_run = arguments.fetch("dry_run", true)
          importer = ::Sequences::IntercomSeriesImporter.for_team(
            context.team,
            spec: spec_for(arguments, intercom_id),
            exports: {intercom_id => export},
            only: [intercom_id],
            sender_address_id: arguments["sender_address_id"],
            email_template_id: arguments["email_template_id"],
            dry_run: dry_run
          )
          results = importer.call.map { serialize(it) }
          segments_key = dry_run ? :segments_to_create : :segments_created
          {dry_run: dry_run, sequences_enabled: context.team.sequences_enabled?, results: results}
            .merge(segments_key => importer.created_segments)
        rescue ::Sequences::IntercomSeriesImporter::SpecError => e
          raise Mcp::Tool::ArgumentError, e.message
        end

        private

        STATUS = {created: "created", would_create: "would_create", exists: "skipped"}.freeze

        def serialize(result)
          {
            intercom_id: result.intercom_id,
            name: result.name,
            status: STATUS.fetch(result.status),
            sequence_id: result.sequence&.id,
            sequence_status: result.sequence&.status,
            steps: result.steps,
            segments: result.segments,
            excluded_sequences: result.excluded,
            warnings: result.warnings,
            changes: result.changes
          }
        end

        # A full spec ({segments, series}) or one series entry, normalized to
        # the full shape the importer reads.
        def spec_for(arguments, intercom_id)
          spec = parse(arguments["spec"], "spec")
          spec = {"series" => [spec]} if spec.key?("intercom_id")
          segments = arguments["segments"] ? parse(arguments["segments"], "segments") : {}
          spec = spec.merge("segments" => Array(spec["segments"]).to_h.merge(segments))
          unless Array(spec["series"]).any? { it["intercom_id"].to_s == intercom_id.to_s }
            raise Mcp::Tool::ArgumentError, "spec has no series entry with intercom_id #{intercom_id}"
          end
          spec
        end

        # Objects arrive with symbol keys from the transport; strings may be
        # JSON or YAML (port.yml as-is).
        def parse(value, field)
          value = parse_string(value) if value.is_a?(String)
          raise Mcp::Tool::ArgumentError, "#{field} must be an object" unless value.is_a?(Hash)
          value.deep_stringify_keys
        rescue Psych::Exception => e
          raise Mcp::Tool::ArgumentError, "#{field} isn't valid JSON or YAML: #{e.message}"
        end

        def parse_string(value)
          JSON.parse(value)
        rescue JSON::ParserError
          YAML.safe_load(value)
        end
      end
    end
  end
end
