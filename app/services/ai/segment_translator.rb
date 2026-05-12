# frozen_string_literal: true

module AI
  # Translates a natural-language audience description into a safe SQL WHERE
  # predicate scoped to `subscribers`. Pairs the predicate with a human-readable
  # description, an estimated count, and a few sample subscribers for the UI.
  #
  # In stub mode (no API key, or `AI::Base.force_stub`), returns a deterministic
  # canned result so the rest of the app can exercise the flow offline.
  class SegmentTranslator < Base
    Result = Struct.new(
      :sql_predicate, :human_description, :sample_subscribers,
      :estimated_count, :errors, :stub,
      keyword_init: true
    ) do
      def success?
        errors.blank? && sql_predicate.present?
      end

      def stub?
        !!stub
      end
    end

    # Tokens that immediately disqualify a predicate. Even if they appear as
    # substrings inside a string literal we'd rather reject than risk it; users
    # can rephrase.
    FORBIDDEN_TOKENS = %w[
      DROP DELETE INSERT UPDATE TRUNCATE ALTER GRANT REVOKE CREATE
      ATTACH DETACH COPY VACUUM EXEC EXECUTE CALL
      ; -- /*
    ].freeze

    # Columns on `subscribers` that we allow the LLM to reference directly.
    ALLOWED_COLUMNS = %w[
      id team_id external_id email name subscribed
      unsubscribed_at complained_at bounced_at
      custom_attributes created_at updated_at
    ].freeze

    MAX_SAMPLE = 5

    def initialize(team:, natural_language:)
      super()
      @team = team
      @natural_language = natural_language.to_s.strip
    end

    def call
      return stub_result if stub_mode?
      return stub_result if @natural_language.blank?

      raw = ask_llm(system: system_prompt, user: user_prompt)
      parsed = parse_json(raw)
      return stub_result(errors: ["LLM did not return valid JSON"]) unless parsed

      predicate = parsed["predicate"].to_s.strip
      description = parsed["description"].to_s.strip.presence ||
        "Subscribers matching: #{@natural_language}"

      validation_errors = validate_predicate(predicate)
      if validation_errors.any?
        return stub_result(errors: validation_errors)
      end

      build_result(sql_predicate: predicate, human_description: description)
    rescue => e
      Rails.logger.warn("[AI::SegmentTranslator] #{e.class}: #{e.message}")
      stub_result(errors: ["AI translation failed: #{e.message}"])
    end

    private

    def system_prompt
      <<~PROMPT
        You translate plain-English audience descriptions into a single SQL WHERE
        predicate over the `subscribers` table. The database is SQLite.
        Subscribers have these columns:

        #{ALLOWED_COLUMNS.join(", ")}

        `custom_attributes` is a JSON column. Reference its keys with SQLite's
        json_extract function, e.g. `json_extract(custom_attributes, '$.plan')
        = 'pro'`. Booleans on SQLite are stored as integers — use `subscribed
        = 1` (true) and `subscribed = 0` (false), not `subscribed = true`.

        Observed custom_attributes keys + types for this team:
        #{custom_attribute_schema(@team).map { |k, t| "  - #{k} (#{t})" }.join("\n").presence || "  (none yet)"}

        Observed event names (for context — do NOT join the events table; if the
        user asks about events, decline politely and suggest filtering on
        custom_attributes instead):
        #{observed_event_names(@team).map { |n| "  - #{n}" }.join("\n").presence || "  (none yet)"}

        Constraints:
        - Output a single SQL fragment safe to drop into `Subscriber.where(...)`.
        - Reference ONLY the `subscribers` columns listed above.
        - No semicolons, no comments, no statements (only a WHERE predicate body).
        - No DROP / DELETE / INSERT / UPDATE / TRUNCATE / ALTER / GRANT.
        - No subqueries against other tables.

        Respond as JSON only, with no surrounding prose:
        {"predicate": "<sql>", "description": "<human readable>", "confidence": 0.0}
      PROMPT
    end

    def user_prompt
      "Describe the audience: #{@natural_language}"
    end

    def validate_predicate(predicate)
      errors = []
      return ["Predicate is blank"] if predicate.blank?

      upcased = predicate.upcase
      FORBIDDEN_TOKENS.each do |tok|
        if upcased.include?(tok)
          errors << "Predicate contains forbidden token: #{tok}"
        end
      end

      # Disallow references to other table names — we only allow bare column
      # names from the subscribers table or `json_extract(custom_attributes,
      # '$.key')` JSON access. A simple heuristic: any identifier of the
      # form `something.something` that isn't `custom_attributes.something`
      # is suspicious.
      predicate.scan(/\b([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)/) do |left, _right|
        next if left.casecmp("subscribers").zero?
        errors << "Predicate references disallowed table: #{left}"
      end

      errors.uniq
    end

    def build_result(sql_predicate:, human_description:)
      scope = @team.subscribers.where(sql_predicate)
      samples = scope.limit(MAX_SAMPLE).to_a
      count = scope.count
      Result.new(
        sql_predicate: sql_predicate,
        human_description: human_description,
        sample_subscribers: samples,
        estimated_count: count,
        errors: [],
        stub: false
      )
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn("[AI::SegmentTranslator] predicate failed to execute: #{e.message}")
      stub_result(errors: ["Predicate failed to execute: #{e.message.split("\n").first}"])
    end

    def stub_result(errors: [])
      scope = @team.subscribers.subscribed
      Result.new(
        # SQLite stores booleans as integers (0/1). Using `= 1` keeps this
        # literal predicate valid on SQLite while remaining equivalent to
        # the prior Postgres `= true` form.
        sql_predicate: "subscribed = 1",
        human_description: "All subscribed subscribers (stub mode — no LLM call)",
        sample_subscribers: scope.limit(MAX_SAMPLE).to_a,
        estimated_count: scope.count,
        errors: errors,
        stub: true
      )
    end
  end
end
