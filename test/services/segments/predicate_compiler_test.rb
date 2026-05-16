require "test_helper"

module Segments
  class PredicateCompilerTest < ActiveSupport::TestCase
    setup do
      @team = create(:team)
    end

    # ── basic shapes ───────────────────────────────────────────────────────

    test "empty tree returns nil" do
      assert_nil PredicateCompiler.new({"type" => "group", "rules" => []}, team: @team).to_sql
    end

    test "single rule wraps in a group with one element" do
      sql = compile({
        "type" => "group", "combinator" => "and",
        "rules" => [
          {"type" => "rule", "field" => "subscribers.subscribed",
           "operator" => "equals", "value" => true}
        ]
      })
      assert_equal "(subscribers.subscribed = 1)", sql
    end

    test "AND combinator joins with AND" do
      sql = compile({
        "type" => "group", "combinator" => "and",
        "rules" => [
          {"type" => "rule", "field" => "subscribers.subscribed", "operator" => "equals", "value" => true},
          {"type" => "rule", "field" => "subscribers.email", "operator" => "contains", "value" => "@example.com"}
        ]
      })
      assert_match(/subscribers\.subscribed = 1/, sql)
      assert_match(/subscribers\.email LIKE '%@example\.com%'/, sql)
      assert_match(/ AND /, sql)
    end

    test "OR combinator joins with OR" do
      sql = compile({
        "type" => "group", "combinator" => "or",
        "rules" => [
          {"type" => "rule", "field" => "subscribers.subscribed", "operator" => "equals", "value" => true},
          {"type" => "rule", "field" => "subscribers.email", "operator" => "contains", "value" => "@foo.com"}
        ]
      })
      assert_match(/ OR /, sql)
    end

    test "nested groups compile recursively" do
      sql = compile({
        "type" => "group", "combinator" => "and",
        "rules" => [
          {"type" => "rule", "field" => "subscribers.subscribed", "operator" => "equals", "value" => true},
          {"type" => "group", "combinator" => "or", "rules" => [
            {"type" => "rule", "field" => "subscribers.email", "operator" => "contains", "value" => "@a.com"},
            {"type" => "rule", "field" => "subscribers.email", "operator" => "contains", "value" => "@b.com"}
          ]}
        ]
      })
      assert_includes sql, "subscribers.subscribed = 1"
      assert_includes sql, "subscribers.email LIKE '%@a.com%' OR subscribers.email LIKE '%@b.com%'"
      assert_match(/\(subscribers\.subscribed.*AND.*\(.*OR.*\)\)/m, sql)
    end

    # ── operator coverage ──────────────────────────────────────────────────

    test "string equals / not_equals" do
      assert_equal "(subscribers.name = 'Alice')",  rule("subscribers.name", "equals", "Alice")
      assert_equal "(subscribers.name != 'Alice')", rule("subscribers.name", "not_equals", "Alice")
    end

    test "string starts_with / ends_with / contains / not_contains" do
      assert_includes rule("subscribers.email", "starts_with", "alice"), "LIKE 'alice%'"
      assert_includes rule("subscribers.email", "ends_with", ".com"),   "LIKE '%.com'"
      assert_includes rule("subscribers.email", "contains", "@"),       "LIKE '%@%'"
      assert_includes rule("subscribers.email", "not_contains", "@"),   "NOT LIKE '%@%'"
    end

    test "string is_set / is_not_set" do
      assert_includes rule("subscribers.name", "is_set", nil),     "subscribers.name IS NOT NULL AND subscribers.name != ''"
      assert_includes rule("subscribers.name", "is_not_set", nil), "subscribers.name IS NULL OR subscribers.name = ''"
    end

    test "string in operator with multiple values" do
      sql = rule("subscribers.email", "in", ["a@x.com", "b@x.com", "c@x.com"])
      assert_includes sql, "subscribers.email IN ('a@x.com','b@x.com','c@x.com')"
    end

    test "datetime within_last_days emits a UTC bound" do
      sql = rule("subscribers.created_at", "within_last_days", 7)
      assert_match(/subscribers\.created_at >= '\d{4}-\d{2}-\d{2}/, sql)
    end

    test "datetime more_than_days_ago" do
      sql = rule("subscribers.created_at", "more_than_days_ago", 30)
      assert_match(/subscribers\.created_at < '\d{4}/, sql)
    end

    test "boolean equals coerces true/false correctly" do
      assert_equal "(subscribers.subscribed = 1)", rule("subscribers.subscribed", "equals", true)
      assert_equal "(subscribers.subscribed = 0)", rule("subscribers.subscribed", "equals", false)
      assert_equal "(subscribers.subscribed = 1)", rule("subscribers.subscribed", "equals", "true")
      assert_equal "(subscribers.subscribed = 0)", rule("subscribers.subscribed", "equals", "false")
    end

    # ── custom attributes ──────────────────────────────────────────────────

    test "custom_attributes resolves via json_extract" do
      sql = rule("custom_attributes.plan", "equals", "growth")
      assert_includes sql, "json_extract(subscribers.custom_attributes, '$.plan') = 'growth'"
    end

    test "company_attributes resolves via json_extract on companies" do
      sql = rule("company_attributes.tenant_type", "equals", "brand")
      assert_includes sql, "json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'"
    end

    test "custom_attributes with hyphen in key is allowed (safe)" do
      sql = rule("custom_attributes.acme-corp-id", "equals", "x")
      assert_includes sql, "$.acme-corp-id"
    end

    # ── security: injection attempts ───────────────────────────────────────

    test "value injection: quotes escaped in equals" do
      sql = rule("subscribers.name", "equals", "x' OR 1=1 --")
      # The quote should be doubled (SQLite/AR), not naively concatenated.
      refute_includes sql, "'x' OR 1=1"
      assert_includes sql, "''"  # AR escapes ' as ''
    end

    test "value injection: LIKE wildcards in contains are escaped" do
      sql = rule("subscribers.name", "contains", "100%off")
      # The % should be backslash-escaped so it's matched literally.
      assert_includes sql, '\\%off'
    end

    test "field whitelist rejects arbitrary SQL identifiers" do
      assert_raises(PredicateCompiler::InvalidTree) do
        rule("subscribers.password", "equals", "x")
      end
      assert_raises(PredicateCompiler::InvalidTree) do
        rule("users.password_digest", "equals", "x")
      end
    end

    test "custom_attribute key is rejected if it contains quotes or semicolons" do
      assert_raises(PredicateCompiler::InvalidTree) do
        rule("custom_attributes.foo'; DROP TABLE users; --", "equals", "x")
      end
    end

    test "unknown operator rejected for its field type" do
      assert_raises(PredicateCompiler::InvalidTree) do
        rule("subscribers.subscribed", "contains", "xyz")  # contains not valid for boolean
      end
    end

    test "unknown combinator rejected" do
      assert_raises(PredicateCompiler::InvalidTree) do
        compile({"type" => "group", "combinator" => "xor", "rules" => [
          {"type" => "rule", "field" => "subscribers.subscribed", "operator" => "equals", "value" => true}
        ]})
      end
    end

    test "unknown node type rejected" do
      assert_raises(PredicateCompiler::InvalidTree) do
        compile({"type" => "spaghetti", "rules" => []})
      end
    end

    # ── round-trip with the actual database ────────────────────────────────

    test "compiled SQL is executable against subscribers" do
      @team.subscribers.create!(email: "a@example.com", external_id: "a1", subscribed: true,
        custom_attributes: {"plan" => "pro"})
      @team.subscribers.create!(email: "b@example.com", external_id: "b1", subscribed: false,
        custom_attributes: {"plan" => "free"})

      sql = compile({
        "type" => "group", "combinator" => "and",
        "rules" => [
          {"type" => "rule", "field" => "subscribers.subscribed", "operator" => "equals", "value" => true},
          {"type" => "rule", "field" => "custom_attributes.plan", "operator" => "equals", "value" => "pro"}
        ]
      })

      result = @team.subscribers.where(sql)
      assert_equal 1, result.count
      assert_equal "a@example.com", result.first.email
    end

    test "compiled SQL with company join is executable" do
      acme = @team.companies.create!(name: "Acme", custom_attributes: {"tenant_type" => "brand"})
      widg = @team.companies.create!(name: "Widget", custom_attributes: {"tenant_type" => "agency"})
      @team.subscribers.create!(email: "a@acme.com", external_id: "a1", subscribed: true, company: acme)
      @team.subscribers.create!(email: "b@widget.com", external_id: "b1", subscribed: true, company: widg)

      sql = compile({
        "type" => "group", "combinator" => "and",
        "rules" => [
          {"type" => "rule", "field" => "company_attributes.tenant_type", "operator" => "equals", "value" => "brand"}
        ]
      })

      result = @team.subscribers.joins(:company).where(sql)
      assert_equal 1, result.count
      assert_equal "a@acme.com", result.first.email
    end

    private

    def compile(tree)
      PredicateCompiler.new(tree, team: @team).to_sql
    end

    # Convenience for single-rule cases.
    def rule(field, operator, value)
      compile({
        "type" => "group", "combinator" => "and",
        "rules" => [{"type" => "rule", "field" => field, "operator" => operator, "value" => value}]
      })
    end
  end
end
