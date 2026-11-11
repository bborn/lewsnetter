class Segment < ApplicationRecord
  # 🚅 add concerns above.

  # Audit trail — every create/update/destroy creates a `versions` row with a
  # column-level diff in `object_changes`. The `definition` JSON column carries
  # the SQL predicate that decides who gets a campaign, so versioning here is
  # how we answer "what predicate ran when we sent that?".
  # See ApplicationController#user_for_paper_trail for whodunnit.
  has_paper_trail on: [:create, :update, :destroy],
    ignore: [:updated_at]

  # Forbidden tokens kept in sync with AI::SegmentTranslator::FORBIDDEN_TOKENS —
  # defense in depth at the job/scope-application layer. If the AI service
  # ever changes how predicates are sourced (UI builder, manual edit, etc.)
  # we still refuse to execute anything that looks like a statement.
  FORBIDDEN_PREDICATE_TOKENS = %w[
    DROP DELETE INSERT UPDATE TRUNCATE ALTER GRANT REVOKE CREATE
    ATTACH DETACH COPY VACUUM EXEC EXECUTE CALL
    ; -- /*
  ].freeze

  # Predicates are raw SQL WHERE fragments that run against the one SQLite
  # database every team shares, so a denylist is not enough: a SELECT inside
  # the predicate could read any table, and the matching count leaks the
  # answer. validate_predicate is an allowlist instead. Every bare word must
  # be a known SQL keyword or function, a column of a segment table, or a
  # segment table itself, and tables may only be read through FROM. Every
  # FROM is then rewritten to a team-scoped derived table (see
  # scope_subqueries), so a subquery can't see another team's rows either.
  SEGMENT_TABLES = %w[subscribers companies events deliveries].freeze
  # Tables a predicate may reference as `table.column` at the top level.
  # events/deliveries only exist inside a subquery's FROM.
  QUALIFIABLE_TABLES = %w[subscribers companies].freeze
  ALLOWED_SQL_WORDS = %w[
    and or not in is null like glob between escape collate nocase
    cast as integer real text numeric
    select distinct from where exists case when then else end
    true false
    coalesce ifnull nullif lower upper trim ltrim rtrim length substr instr
    replace abs round min max count typeof
    datetime date time julianday strftime unixepoch
    json_extract json_each json_array_length json_type json_valid
    key value type atom fullkey path
  ].freeze

  class InvalidPredicate < StandardError; end

  # 🚅 add attribute accessors above.

  belongs_to :team

  has_many :campaigns, dependent: :restrict_with_error

  validates :name, presence: true
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # Returns the SQL WHERE fragment stored in definition["predicate"], or nil
  # if the segment has no predicate (e.g. UI not yet wired, AI returned empty).
  def predicate
    definition.is_a?(Hash) ? definition["predicate"].to_s.strip.presence : nil
  end

  # Virtual setter so the segment form can post a predicate alongside the
  # other fields. We write into the `definition` JSON column rather than
  # introducing a new schema column. Blanks clear the predicate entirely.
  def predicate=(value)
    self.definition ||= {}
    new_pred = value.to_s.strip
    self.definition = if new_pred.blank?
      definition.is_a?(Hash) ? definition.except("predicate") : {}
    else
      (definition.is_a?(Hash) ? definition : {}).merge("predicate" => new_pred)
    end
  end

  # Visual builder rule tree (parsed JSON). Empty hash → segment has no
  # tree (was hand-edited or legacy). When set, the before_save callback
  # compiles it to the `predicate` column for the existing send pipeline.
  def rules
    definition.is_a?(Hash) ? (definition["rules"] || {}) : {}
  end

  def rules=(value)
    self.definition ||= {}
    tree = value.is_a?(String) ? begin
      JSON.parse(value)
    rescue
      nil
    end : value
    self.definition = definition.merge("rules" => tree).compact
    @rules_changed = true
  end

  # Compile the rule tree to a SQL predicate whenever it changes. Keeps
  # the legacy predicate column in sync so Segment#applies_to (used by
  # SendCampaignJob and the MCP segment tools) keeps working unchanged.
  before_save :compile_rules_to_predicate, if: -> { @rules_changed }
  def compile_rules_to_predicate
    return if rules.blank?
    sql = Segments::PredicateCompiler.new(rules, team: team).to_sql
    self.predicate = sql
  rescue Segments::PredicateCompiler::InvalidTree => e
    errors.add(:base, "Segment rules are invalid: #{e.message}")
    throw :abort
  end

  # Apply this segment's predicate to an existing ActiveRecord scope and return
  # the narrowed scope. If there's no predicate the scope is returned as-is.
  # Raises Segment::InvalidPredicate if the stored predicate contains any
  # forbidden SQL keyword — callers (notably SendCampaignJob) catch this and
  # transition the campaign to failed with a useful error message.
  def applies_to(scope)
    pred = predicate
    return scope if pred.blank?

    validation_errors = self.class.validate_predicate(pred)
    if validation_errors.any?
      raise InvalidPredicate, "Segment #{id} has invalid predicate: #{validation_errors.join(", ")}"
    end

    # Auto-join companies when the predicate references the companies table
    # (or its JSON custom_attributes). We can't reach company-level columns
    # without a JOIN, and asking the AI translator (or a hand author) to spell
    # out joins is fragile, so the segment layer handles it.
    scope = scope.joins(:company) if pred.match?(/\bcompanies\./i)
    scope.where(self.class.scope_subqueries(pred, team_id))
  end

  # Rewrites every `FROM <segment table>` outside string literals to a
  # derived table holding only this team's rows, so a subquery like
  # `id NOT IN (SELECT subscriber_id FROM events WHERE ...)` reads the
  # team's own events. Run only on predicates validate_predicate accepted.
  def self.scope_subqueries(predicate, team_id)
    team_id = Integer(team_id)
    predicate.gsub(/'(?:[^']|'')*'|\bFROM\s+(#{SEGMENT_TABLES.join("|")})\b/i) do |match|
      table = Regexp.last_match(1)&.downcase
      next match if table.nil? # a string literal, left untouched

      scoped = if table == "deliveries"
        "SELECT * FROM deliveries WHERE campaign_id IN (SELECT id FROM campaigns WHERE team_id = #{team_id})"
      else
        "SELECT * FROM #{table} WHERE team_id = #{team_id}"
      end
      "FROM (#{scoped}) #{table}"
    end
  end

  def self.allowed_predicate_words
    @allowed_predicate_words ||= (
      ALLOWED_SQL_WORDS + SEGMENT_TABLES +
      [Subscriber, Company, Event, Delivery].flat_map(&:column_names)
    ).map(&:downcase).to_set
  end

  # Mirror of AI::SegmentTranslator#validate_predicate. Returns an array of
  # error messages; empty array means the predicate passes the allowlist.
  def self.validate_predicate(predicate)
    errors = []
    return ["Predicate is blank"] if predicate.to_s.strip.blank?

    # Keywords match as whole words so columns like created_at / updated_at
    # stay usable; punctuation tokens (; -- /*) match anywhere.
    upcased = predicate.upcase
    FORBIDDEN_PREDICATE_TOKENS.each do |tok|
      hit = tok.match?(/\A[A-Z]+\z/) ? upcased.match?(/\b#{tok}\b/) : upcased.include?(tok)
      errors << "Predicate contains forbidden token: #{tok}" if hit
    end

    # Ignore single-quoted string literals when scanning for table references.
    # A quoted value like 'gmail.com' or 'reports.acme.com' is data, not a
    # `table.column` reference, and would otherwise be rejected as a disallowed
    # table — which blocks legitimate domain/email segments. Handles SQL-escaped
    # quotes ('') inside the literal. (The forbidden-token check above still
    # scans the full predicate.)
    scannable = predicate.gsub(/'(?:[^']|'')*'/, "''")
    scannable.scan(/\b([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)/) do |left, _right|
      next if QUALIFIABLE_TABLES.include?(left.downcase)
      errors << "Predicate references disallowed table: #{left}"
    end

    # Quoted identifiers ("users", `users`, [users]) would slip a table name
    # past the FROM rewrite below.
    if scannable.match?(/["`\[\]]/)
      errors << "Predicate may not use quoted identifiers"
    end

    scannable.scan(/\b[a-zA-Z_][a-zA-Z0-9_]*\b/) do |word|
      next if allowed_predicate_words.include?(word.downcase)
      errors << "Predicate uses unknown word: #{word}"
    end

    # A segment table may appear only as `FROM <table>` (one table, no comma
    # join) or, for subscribers/companies, as a `table.column` prefix.
    scannable.scan(/(\w+\s*)?\b(#{SEGMENT_TABLES.join("|")})\b(\s*[.,])?/i) do |before, table, after|
      after = after.to_s.strip
      from = before.to_s.strip.casecmp("from").zero?
      qualified = after == "." && QUALIFIABLE_TABLES.include?(table.downcase)
      next if (from && after != "," && after != ".") || qualified
      errors << "Predicate may read #{table} only through a single FROM #{table}"
    end
    if scannable.match?(/\bFROM\b(?!\s*(?:#{SEGMENT_TABLES.join("|")})\b|\s*json_each\s*\()/i)
      errors << "Predicate may only select FROM #{SEGMENT_TABLES.join(", ")} or json_each(...)"
    end

    errors.uniq
  end
  # 🚅 add methods above.
end
