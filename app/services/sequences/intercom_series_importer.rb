# Builds draft Sequences from an Intercom Series export, following a port
# spec that says how each branching series flattens into steps. The spec is
# the judgment (which email comes when, which condition becomes a skip
# segment or a step action); this class is the mechanics (pull the email
# bodies out of the export, create segments, sequences and steps).
#
# Everything is created as a draft, so nothing sends until someone reviews
# and activates it. Nothing is enrolled and the team's sequences_enabled flag
# is never touched. Re-running skips any sequence whose name already exists.
# Only the segments the imported series reference are created.
#
# Two callers share this class: the `sequences:import_intercom_series` rake
# task (a directory of exports, the whole spec) and the
# `sequences_import_intercom` MCP tool (one inline export per call). Both go
# through `.for_team`, which resolves the sender address and email template
# on the team. `dry_run: true` runs the same import inside a transaction and
# rolls it back, so the report is exactly what a real run would create.
#
# Spec (string keys, usually from YAML):
#
#   segments:
#     Never connected: {rules: {...}}          # or {predicate: "..."}
#   series:
#     - intercom_id: 381681
#       name: Connect accounts                 # default: the series title
#       trigger: {segment: Never connected}    # or {event: signed_up}
#       exclude: [378582]                      # intercom ids or names
#       reentry_days: 90                       # omit for once ever
#       goal: {event: account:connected}       # and/or {segment: ...}
#       exit_segment: Connected
#       finish_after_days: 3
#       completed_tag: Didn't connect
#       steps:
#         - email: 43856798                    # the email's ruleset id
#           wait_days: 0                       # or wait_hours / wait_minutes
#           skip_segment: Connected
#           sent_tag: ...
#           action: {on: goal, tag: Connected, exit: true}
#       changes: ["…"]                         # echoed into the report
module Sequences
  class IntercomSeriesImporter
    Result = Struct.new(:intercom_id, :name, :status, :sequence, :steps, :segments, :excluded,
      :warnings, :changes, keyword_init: true)

    class SpecError < StandardError; end

    # Ids are looked up on the team, so another team's sender address or
    # template raises RecordNotFound. Without a template, steps are plain
    # text and the markdown ships raw, so a real run refuses to go ahead.
    def self.for_team(team, spec:, sender_address_id: nil, email_template_id: nil, **options)
      email_template = email_template_id.presence && team.email_templates.find_by!(id: email_template_id)
      if email_template.nil? && !options[:dry_run]
        raise SpecError, "an email template is required (email_template_id)"
      end
      new(team: team, spec: spec, email_template: email_template,
        sender_address: sender_address_id.presence && team.sender_addresses.find_by!(id: sender_address_id),
        **options)
    end

    attr_reader :created_segments

    # export_dir: a directory of <intercom_id>.json files, or
    # exports: {intercom_id => parsed export}.
    # only: intercom ids to import; the other spec entries only name
    # `exclude` references. Default: every series in the spec.
    def initialize(team:, spec:, export_dir: nil, exports: nil, only: nil, sender_address: nil,
      email_template: nil, dry_run: false)
      @team = team
      @spec = spec
      @export_dir = export_dir && Pathname(export_dir)
      @exports = (exports || {}).transform_keys(&:to_s)
      @only = only&.map(&:to_s)
      @sender_address = sender_address
      @email_template = email_template
      @dry_run = dry_run
    end

    def call
      results = []
      created = {}
      @segments = {}
      @created_segments = []
      # requires_new: a savepoint, so the dry-run rollback holds even when
      # the caller is already inside a transaction.
      Sequence.transaction(requires_new: true) do
        entries.each do |entry|
          result = import_series(entry)
          created[entry["intercom_id"].to_s] = result.sequence if result.status == :created
          results << result
        end
        link_exclusions(entries.zip(results), created)
        raise ActiveRecord::Rollback if @dry_run
      end
      return results unless @dry_run

      results.each do |r|
        next unless r.status == :created
        r.status = :would_create
        r.sequence = nil
      end
    end

    private

    def entries
      @entries ||= Array(@spec["series"]).select { |e| @only.nil? || @only.include?(e["intercom_id"].to_s) }
    end

    def segment_definitions
      @segment_definitions ||= Array(@spec["segments"]).to_h
    end

    def create_segment(name, definition)
      segment = if definition["rules"]
        @team.segments.create!(name: name, rules: definition["rules"])
      elsif definition["predicate"]
        @team.segments.create!(name: name, definition: {"predicate" => definition["predicate"]})
      else
        raise SpecError, "segment #{name.inspect} needs rules or a predicate"
      end
      @created_segments << name
      segment
    end

    def import_series(entry)
      export = load_export(entry.fetch("intercom_id"))
      name = entry["name"].presence || export.dig("series", "title")
      changes = Array(entry["changes"])
      base = {intercom_id: entry["intercom_id"], name: name, changes: changes, segments: [], excluded: []}

      if (existing = @team.sequences.find_by(name: name))
        return Result.new(**base, status: :exists, sequence: existing, steps: existing.steps.size, warnings: [])
      end

      used = []
      segment = ->(segment_name) { segment_for(segment_name)&.tap { used << segment_name } }
      trigger = entry["trigger"] || {}
      goal = entry["goal"] || {}
      sequence = @team.sequences.create!(
        name: name,
        status: "draft",
        trigger_type: trigger["event"] ? "event" : "segment",
        trigger_event_name: trigger["event"],
        trigger_segment: segment.call(trigger["segment"]),
        exit_segment: segment.call(entry["exit_segment"]),
        goal_segment: segment.call(goal["segment"]),
        goal_event_name: goal["event"],
        reentry_days: entry["reentry_days"],
        finish_after_minutes: minutes(entry, "finish_after"),
        completed_tag: entry["completed_tag"],
        sender_address: @sender_address
      )

      warnings = []
      Array(entry["steps"]).each do |step_spec|
        content, step_warnings = email_content(export, step_spec.fetch("email"))
        warnings.concat(step_warnings)
        action = step_spec["action"] || {}
        sequence.steps.create!(
          subject: content[:subject],
          body_markdown: content[:body],
          email_template: @email_template,
          delay_minutes: minutes(step_spec, "wait"),
          skip_segment: segment.call(step_spec["skip_segment"]),
          sent_tag: step_spec["sent_tag"],
          action_trigger: action["on"],
          action_tag: action["tag"],
          action_exit: action["exit"] || false
        )
      end

      Result.new(**base, status: :created, sequence: sequence, steps: sequence.steps.size,
        segments: used.uniq, warnings: warnings.uniq)
    end

    # An `exclude` reference is an intercom id or a sequence name. An id
    # resolves to a series created in this run, or to the sequence named by
    # that id's spec entry if an earlier run (or call) imported it.
    def link_exclusions(pairs, created)
      pairs.each do |entry, result|
        next unless result.status == :created && entry["exclude"].present?
        excluded = Array(entry["exclude"]).filter_map do |ref|
          seq = created[ref.to_s] || @team.sequences.find_by(name: spec_name(ref) || ref.to_s)
          if seq
            next seq
          elsif spec_name(ref)
            result.warnings << "excluded series #{ref} (#{spec_name(ref)}) isn't imported yet: rule dropped; import it first"
          else
            result.warnings << "excluded series #{ref} isn't ported: rule dropped"
          end
          nil
        end
        result.sequence.update!(excluded_sequence_ids: excluded.map(&:id))
        result.excluded = excluded.map(&:name)
      end
    end

    def spec_name(ref)
      entry = Array(@spec["series"]).find { |e| e["intercom_id"].to_s == ref.to_s }
      entry && (entry["name"].presence || @exports[ref.to_s]&.dig("series", "title"))
    end

    def load_export(intercom_id)
      @exports.fetch(intercom_id.to_s) do
        raise SpecError, "no export for series #{intercom_id}" if @export_dir.nil?
        JSON.parse(@export_dir.join("#{intercom_id}.json").read)
      end
    rescue Errno::ENOENT
      raise SpecError, "no export file for series #{intercom_id} in #{@export_dir}"
    end

    # The email node's ruleset holds the content. More than one content
    # object means an A/B test (or a translation); the first is kept.
    def email_content(export, ruleset_id)
      ruleset = export.fetch("rulesets").fetch(ruleset_id.to_s) do
        raise SpecError, "series #{export.dig("series", "id")} has no ruleset #{ruleset_id}"
      end
      contents = Array(ruleset["ruleset_links"]).flat_map { |l| Array(l.dig("object", "localized_email_contents")) }
      raise SpecError, "ruleset #{ruleset_id} is not an email" if contents.empty?

      first = contents.first
      body, warnings = IntercomBlocks.to_markdown(first["blocks"])
      subject = IntercomBlocks.subject(first["subject_blocks"], warnings).presence || ruleset.dig("client_data", "title").to_s
      warnings = warnings.uniq.map { |w| "#{ruleset_id}: #{w}" }
      warnings << "#{ruleset_id}: A/B variant dropped (kept version A)" if contents.size > 1
      [{subject: subject, body: body}, warnings]
    end

    # A segment already on the team wins over the spec's definition, so a
    # re-run (or a second series) reuses it rather than duplicating it.
    def segment_for(name)
      return nil if name.blank?
      @segments[name] ||= @team.segments.find_by(name: name) ||
        (segment_definitions.key?(name) && create_segment(name, segment_definitions[name] || {})) ||
        raise(SpecError, "segment #{name.inspect} is neither in the spec nor on the team")
    end

    def minutes(hash, prefix)
      (hash["#{prefix}_days"].to_f * 1440 + hash["#{prefix}_hours"].to_f * 60 + hash["#{prefix}_minutes"].to_f).round
    end
  end
end
