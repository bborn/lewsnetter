# frozen_string_literal: true

module Segments
  # Compiles a UI-built rule tree into a safe SQL WHERE fragment for the
  # `subscribers` table (with `companies` auto-joined when referenced).
  #
  # Tree shape (parsed from JSON in the segment definition):
  #
  #   {
  #     "type": "group",
  #     "combinator": "and",            # "and" | "or"
  #     "rules": [
  #       {"type": "rule", "field": "subscribers.subscribed",
  #        "operator": "equals", "value": true},
  #       {"type": "group", "combinator": "or", "rules": [...]}
  #     ]
  #   }
  #
  # Security model:
  # - Field names are looked up in a whitelist (FIELDS) — anything else is
  #   rejected. Custom attributes are namespaced under "custom_attributes."
  #   and "company_attributes." and rendered through json_extract with the
  #   key inside ' single quotes (validated to be word-char only).
  # - Values are interpolated via ActiveRecord::Base.sanitize_sql_array so
  #   we never concatenate user strings into SQL directly.
  # - Operators are also enumerated; unknown ops raise.
  #
  # Returns nil when the tree compiles to no rules (so the caller can fall
  # through to "match everything" semantics or treat as empty as needed).
  class PredicateCompiler
    class InvalidTree < StandardError; end

    # Field metadata: SQL expression + value type + label (for the UI).
    # Built-in fields. Custom attributes resolved separately.
    FIELDS = {
      "subscribers.email"           => {sql: "subscribers.email",           type: :string,   label: "Email"},
      "subscribers.name"            => {sql: "subscribers.name",            type: :string,   label: "Name"},
      "subscribers.external_id"     => {sql: "subscribers.external_id",     type: :string,   label: "External ID"},
      "subscribers.subscribed"      => {sql: "subscribers.subscribed",      type: :boolean,  label: "Subscribed"},
      "subscribers.unsubscribed_at" => {sql: "subscribers.unsubscribed_at", type: :datetime, label: "Unsubscribed at"},
      "subscribers.bounced_at"      => {sql: "subscribers.bounced_at",      type: :datetime, label: "Bounced at"},
      "subscribers.complained_at"   => {sql: "subscribers.complained_at",   type: :datetime, label: "Complained at"},
      "subscribers.created_at"      => {sql: "subscribers.created_at",      type: :datetime, label: "Created at"},
      "subscribers.updated_at"      => {sql: "subscribers.updated_at",      type: :datetime, label: "Updated at"},
      "companies.name"              => {sql: "companies.name",              type: :string,   label: "Company name"},
      "companies.external_id"       => {sql: "companies.external_id",       type: :string,   label: "Company external ID"}
    }.freeze

    # Per-type operator catalog. Each operator declares the SQL form and
    # whether it expects a value (some, like is_set, do not).
    OPERATORS = {
      string: %w[equals not_equals contains not_contains starts_with ends_with is_set is_not_set in],
      boolean: %w[equals],
      datetime: %w[before after within_last_days more_than_days_ago is_set is_not_set]
    }.freeze

    SAFE_KEY = /\A[A-Za-z0-9_\-]+\z/

    def initialize(tree, team:)
      @tree = tree.is_a?(String) ? JSON.parse(tree) : tree
      @team = team
    end

    # Returns the WHERE-fragment string, or nil if the tree resolves to
    # no constraints (caller decides what that means).
    def to_sql
      compile_node(@tree)
    end

    private

    def compile_node(node)
      return nil if node.nil?
      case node["type"]
      when "group" then compile_group(node)
      when "rule"  then compile_rule(node)
      else raise InvalidTree, "unknown node type: #{node["type"].inspect}"
      end
    end

    def compile_group(group)
      combinator = (group["combinator"] || "and").to_s.downcase
      raise InvalidTree, "bad combinator #{combinator.inspect}" unless %w[and or].include?(combinator)

      parts = Array(group["rules"]).map { |child| compile_node(child) }.compact.reject(&:empty?)
      return nil if parts.empty?
      "(#{parts.join(" #{combinator.upcase} ")})"
    end

    def compile_rule(rule)
      sql_field, value_type = resolve_field(rule["field"])
      operator = rule["operator"].to_s
      unless OPERATORS.fetch(value_type, []).include?(operator)
        raise InvalidTree, "operator #{operator.inspect} not allowed for #{value_type} field"
      end
      compile_op(sql_field, value_type, operator, rule["value"])
    end

    # Resolves a field key to a (sql_expression, value_type) pair.
    # Built-in fields are looked up in FIELDS. Custom-attribute keys are
    # validated for safety and rendered via json_extract.
    def resolve_field(key)
      return [FIELDS[key][:sql], FIELDS[key][:type]] if FIELDS.key?(key)

      if (m = key.to_s.match(/\Acustom_attributes\.([\w\-]+)\z/))
        attr_key = m[1]
        raise InvalidTree, "unsafe custom attribute key" unless attr_key.match?(SAFE_KEY)
        [%(json_extract(subscribers.custom_attributes, '$.#{attr_key}')), :string]
      elsif (m = key.to_s.match(/\Acompany_attributes\.([\w\-]+)\z/))
        attr_key = m[1]
        raise InvalidTree, "unsafe company attribute key" unless attr_key.match?(SAFE_KEY)
        [%(json_extract(companies.custom_attributes, '$.#{attr_key}')), :string]
      else
        raise InvalidTree, "field #{key.inspect} is not whitelisted"
      end
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
    def compile_op(field, type, op, raw_value)
      case [type, op]
      # ── string ───────────────────────────────────────────────────────────
      when [:string, "equals"]
        sanitize("#{field} = ?", raw_value.to_s)
      when [:string, "not_equals"]
        sanitize("#{field} != ?", raw_value.to_s)
      when [:string, "contains"]
        sanitize("#{field} LIKE ?", "%#{escape_like(raw_value.to_s)}%")
      when [:string, "not_contains"]
        sanitize("#{field} NOT LIKE ?", "%#{escape_like(raw_value.to_s)}%")
      when [:string, "starts_with"]
        sanitize("#{field} LIKE ?", "#{escape_like(raw_value.to_s)}%")
      when [:string, "ends_with"]
        sanitize("#{field} LIKE ?", "%#{escape_like(raw_value.to_s)}")
      when [:string, "is_set"]
        "(#{field} IS NOT NULL AND #{field} != '')"
      when [:string, "is_not_set"]
        "(#{field} IS NULL OR #{field} = '')"
      when [:string, "in"]
        values = Array(raw_value).reject(&:blank?).map(&:to_s)
        return nil if values.empty?
        sanitize("#{field} IN (?)", values)

      # ── boolean ──────────────────────────────────────────────────────────
      when [:boolean, "equals"]
        truthy = ActiveModel::Type::Boolean.new.cast(raw_value)
        # SQLite stores booleans as integers.
        "#{field} = #{truthy ? 1 : 0}"

      # ── datetime ─────────────────────────────────────────────────────────
      when [:datetime, "before"]
        sanitize("#{field} < ?", parse_time(raw_value))
      when [:datetime, "after"]
        sanitize("#{field} > ?", parse_time(raw_value))
      when [:datetime, "within_last_days"]
        days = Integer(raw_value)
        sanitize("#{field} >= ?", days.days.ago)
      when [:datetime, "more_than_days_ago"]
        days = Integer(raw_value)
        sanitize("#{field} < ?", days.days.ago)
      when [:datetime, "is_set"]
        "#{field} IS NOT NULL"
      when [:datetime, "is_not_set"]
        "#{field} IS NULL"

      else
        raise InvalidTree, "unhandled (#{type}, #{op}) combo"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

    def sanitize(template, *args)
      ActiveRecord::Base.sanitize_sql_array([template, *args])
    end

    def escape_like(str)
      str.gsub("\\", "\\\\\\\\").gsub("%", '\\%').gsub("_", '\\_')
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(DateTime)
      Time.zone.parse(value.to_s) || raise(InvalidTree, "bad datetime #{value.inspect}")
    end
  end
end
