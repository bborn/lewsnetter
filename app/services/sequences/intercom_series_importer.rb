# Builds draft Sequences from an Intercom Series export, following a port
# spec that says how each branching series flattens into steps. The spec is
# the judgment (which email comes when, which condition becomes a skip
# segment or a step action); this class is the mechanics (pull the email
# bodies out of the export, create segments, sequences and steps).
#
# Everything is created as a draft, so nothing sends until someone reviews
# and activates it. Re-running skips any sequence whose name already exists.
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
    Result = Struct.new(:name, :status, :sequence, :steps, :warnings, :changes, keyword_init: true)

    class SpecError < StandardError; end

    def initialize(team:, export_dir:, spec:, sender_address: nil, email_template: nil)
      @team = team
      @export_dir = Pathname(export_dir)
      @spec = spec
      @sender_address = sender_address
      @email_template = email_template
    end

    def call
      results = []
      created = {}
      Sequence.transaction do
        segments = build_segments
        Array(@spec["series"]).each do |entry|
          result = import_series(entry, segments)
          created[entry["intercom_id"].to_s] = result.sequence if result.sequence
          results << result
        end
        link_exclusions(results, created)
      end
      results
    end

    private

    def build_segments
      Array(@spec["segments"]).to_h.to_h do |name, definition|
        [name, @team.segments.find_by(name: name) || create_segment(name, definition || {})]
      end
    end

    def create_segment(name, definition)
      if definition["rules"]
        @team.segments.create!(name: name, rules: definition["rules"])
      elsif definition["predicate"]
        @team.segments.create!(name: name, definition: {"predicate" => definition["predicate"]})
      else
        raise SpecError, "segment #{name.inspect} needs rules or a predicate"
      end
    end

    def import_series(entry, segments)
      export = load_export(entry.fetch("intercom_id"))
      name = entry["name"].presence || export.dig("series", "title")
      changes = Array(entry["changes"])

      if (existing = @team.sequences.find_by(name: name))
        return Result.new(name: name, status: :exists, sequence: existing, steps: existing.steps.size,
          warnings: [], changes: changes)
      end

      trigger = entry["trigger"] || {}
      goal = entry["goal"] || {}
      sequence = @team.sequences.create!(
        name: name,
        status: "draft",
        trigger_type: trigger["event"] ? "event" : "segment",
        trigger_event_name: trigger["event"],
        trigger_segment: segment_for(trigger["segment"], segments),
        exit_segment: segment_for(entry["exit_segment"], segments),
        goal_segment: segment_for(goal["segment"], segments),
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
          skip_segment: segment_for(step_spec["skip_segment"], segments),
          sent_tag: step_spec["sent_tag"],
          action_trigger: action["on"],
          action_tag: action["tag"],
          action_exit: action["exit"] || false
        )
      end

      Result.new(name: name, status: :created, sequence: sequence, steps: sequence.steps.size,
        warnings: warnings.uniq, changes: changes)
    end

    def link_exclusions(results, created)
      Array(@spec["series"]).zip(results).each do |entry, result|
        next unless result.status == :created && entry["exclude"].present?
        ids = Array(entry["exclude"]).map do |ref|
          seq = created[ref.to_s] || @team.sequences.find_by(name: ref.to_s)
          if seq.nil?
            result.warnings << "excluded series #{ref} isn't ported: rule dropped"
            next
          end
          seq.id
        end
        result.sequence.update!(excluded_sequence_ids: ids.compact)
      end
    end

    def load_export(intercom_id)
      JSON.parse(@export_dir.join("#{intercom_id}.json").read)
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

    def segment_for(name, segments)
      return nil if name.blank?
      segments[name] || @team.segments.find_by(name: name) ||
        raise(SpecError, "segment #{name.inspect} is neither in the spec nor on the team")
    end

    def minutes(hash, prefix)
      (hash["#{prefix}_days"].to_f * 1440 + hash["#{prefix}_hours"].to_f * 60 + hash["#{prefix}_minutes"].to_f).round
    end
  end
end
