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

    test "string equals / not_equals (not_equals is NULL-permissive)" do
      assert_equal "(subscribers.name = 'Alice')", rule("subscribers.name", "equals", "Alice")
      # not_equals matches rows where the column is NULL too — consistent with
      # Intercom-style "is not Alice" semantics (a missing value trivially is
      # not Alice). Otherwise NULL rows would be silently excluded.
      assert_equal "((subscribers.name IS NULL OR subscribers.name != 'Alice'))",
        rule("subscribers.name", "not_equals", "Alice")
    end

    test "string starts_with / ends_with / contains / not_contains" do
      assert_includes rule("subscribers.email", "starts_with", "alice"), "LIKE 'alice%'"
      assert_includes rule("subscribers.email", "ends_with", ".com"),   "LIKE '%.com'"
      assert_includes rule("subscribers.email", "contains", "@"),       "LIKE '%@%'"
      # NULL-permissive negative: row where email is NULL passes "doesn't
      # contain @" too. The user's bug on prod: tabs_enabled not_contains
      # 'brand' should include rows where tabs_enabled is missing entirely.
      sql = rule("subscribers.email", "not_contains", "@")
      assert_includes sql, "subscribers.email IS NULL"
      assert_includes sql, "NOT LIKE '%@%'"
    end

    test "custom_attributes not_contains is NULL-permissive (the prod bug)" do
      # Regression: not_contains used to silently drop rows where the JSON
      # key was absent (NULL NOT LIKE evaluates to NULL → excluded).
      sql = rule("custom_attributes.tabs_enabled", "not_contains", "brand")
      assert_includes sql, "json_extract(subscribers.custom_attributes, '$.tabs_enabled') IS NULL"
      assert_includes sql, "NOT LIKE '%brand%'"
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

    # ── number type (Intercom-style numeric comparisons) ───────────────────

    test "number equals / not_equals / less_than / greater_than" do
      assert_includes typed_rule("custom_attributes.score", :number, "equals", 42),       "CAST(json_extract(subscribers.custom_attributes, '$.score') AS REAL) = 42.0"
      assert_includes typed_rule("custom_attributes.score", :number, "less_than", 10),    "< 10.0"
      assert_includes typed_rule("custom_attributes.score", :number, "greater_than", 99), "> 99.0"
      # not_equals is NULL-permissive (consistent with strings).
      sql = typed_rule("custom_attributes.score", :number, "not_equals", 0)
      assert_includes sql, "IS NULL"
      assert_includes sql, "!= 0.0"
    end

    test "number between expects [lo, hi]" do
      sql = typed_rule("custom_attributes.score", :number, "between", [10, 90])
      assert_includes sql, "BETWEEN 10.0 AND 90.0"
    end

    test "number rejects non-numeric values" do
      assert_raises(PredicateCompiler::InvalidTree) do
        typed_rule("custom_attributes.score", :number, "equals", "not-a-number")
      end
    end

    # ── array type (element-wise membership) ───────────────────────────────

    test "array contains uses json_each for element matching" do
      sql = typed_rule("custom_attributes.tabs_enabled", :array, "contains", "brand")
      assert_includes sql, "EXISTS (SELECT 1 FROM json_each(json_extract(subscribers.custom_attributes, '$.tabs_enabled')) WHERE value = 'brand')"
    end

    test "array not_contains is NULL-permissive + uses NOT EXISTS" do
      sql = typed_rule("custom_attributes.tabs_enabled", :array, "not_contains", "brand")
      assert_includes sql, "json_extract(subscribers.custom_attributes, '$.tabs_enabled') IS NULL"
      assert_includes sql, "NOT EXISTS"
    end

    test "array is_set treats empty array as 'not set'" do
      assert_includes typed_rule("custom_attributes.tabs_enabled", :array, "is_set",     nil), "json_array_length"
      assert_includes typed_rule("custom_attributes.tabs_enabled", :array, "is_not_set", nil), "json_array_length"
    end

    # ── csv_list type (anchored substring matching) ────────────────────────

    test "csv_list contains uses anchored commas to prevent prefix collisions" do
      # The exact prod-data shape: tabs_enabled = "billing,brand_account,..."
      # Naive substring "contains brand" would match brand_account; anchored
      # matching with surrounding commas does NOT.
      sql = typed_rule("custom_attributes.tabs_enabled", :csv_list, "contains", "brand")
      assert_includes sql, "',' || COALESCE(json_extract"
      assert_includes sql, "LIKE '%,brand,%'"
    end

    test "csv_list not_contains is NULL-permissive" do
      sql = typed_rule("custom_attributes.tabs_enabled", :csv_list, "not_contains", "brand")
      assert_includes sql, "IS NULL"
      assert_includes sql, "NOT LIKE '%,brand,%'"
    end

    test "csv_list end-to-end: 'contains brand' does not match brand_account" do
      @team.subscribers.create!(email: "brand-only@example.com", external_id: "co",
        subscribed: true, custom_attributes: {"tabs_enabled" => "brand_account,reports"})
      @team.subscribers.create!(email: "real-brand@example.com", external_id: "rb",
        subscribed: true, custom_attributes: {"tabs_enabled" => "brand,reports"})

      sql = typed_rule("custom_attributes.tabs_enabled", :csv_list, "contains", "brand")
      emails = @team.subscribers.where(sql).pluck(:email)
      refute_includes emails, "brand-only@example.com"
      assert_includes emails, "real-brand@example.com"
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

    # Round-trip: real subscribers, array-valued tabs_enabled,
    # not_contains must include the row with no tabs_enabled at all.
    test "array not_contains matches subscribers missing the key (prod bug)" do
      @team.subscribers.create!(email: "all-tabs@example.com", external_id: "a",
        subscribed: true, custom_attributes: {"tabs_enabled" => ["brand", "manager"]})
      @team.subscribers.create!(email: "manager-only@example.com", external_id: "m",
        subscribed: true, custom_attributes: {"tabs_enabled" => ["manager"]})
      @team.subscribers.create!(email: "no-attrs@example.com", external_id: "n",
        subscribed: true, custom_attributes: {})

      sql = typed_rule("custom_attributes.tabs_enabled", :array, "not_contains", "brand")
      emails = @team.subscribers.where(sql).pluck(:email)
      # The "all-tabs" row must be excluded; both manager-only and no-attrs
      # must be included.
      refute_includes emails, "all-tabs@example.com"
      assert_includes emails, "manager-only@example.com"
      assert_includes emails, "no-attrs@example.com"
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

    # Same as `rule`, plus a value_type hint (required for non-string custom
    # attributes — without it the compiler defaults to :string).
    def typed_rule(field, value_type, operator, value)
      compile({
        "type" => "group", "combinator" => "and",
        "rules" => [{"type" => "rule", "field" => field, "value_type" => value_type.to_s,
                     "operator" => operator, "value" => value}]
      })
    end
  end
end
