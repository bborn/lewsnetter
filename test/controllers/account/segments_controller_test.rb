require "test_helper"

class Account::SegmentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  test "show renders the segment name, description, predicate, and audience count" do
    @team.subscribers.create!(email: "alice@example.com", name: "Alice", subscribed: true)
    @team.subscribers.create!(email: "bob@example.com", name: "Bob", subscribed: false)
    segment = @team.segments.create!(
      name: "Subscribed folks",
      natural_language_source: "Everyone who's still subscribed.",
      definition: {"predicate" => "subscribed = 1"}
    )

    get account_segment_url(segment)
    assert_response :success
    # Description is the new label for natural_language_source (U32).
    assert_match(/Description/, response.body)
    assert_match(/Everyone who&#39;s still subscribed/, response.body)
    # Compiled predicate is visible (U6).
    assert_match(/subscribed = 1/, response.body)
    # Audience count + at least one matching subscriber email is rendered.
    # Allow the HTML to wrap the count in a <strong> tag and span newlines.
    assert_match(/<strong>1<\/strong>\s*subscriber match/m, response.body)
    assert_match(/alice@example.com/, response.body)
    # The unsubscribed subscriber shouldn't appear in the audience sample.
    assert_no_match(/bob@example.com/, response.body)
  end

  test "show renders empty predicate state gracefully" do
    segment = @team.segments.create!(
      name: "Empty",
      natural_language_source: "No predicate yet."
    )

    get account_segment_url(segment)
    assert_response :success
    assert_match(/No predicate set yet/, response.body)
  end

  test "edit lists an attribute the segment uses even when no subscriber has it yet" do
    segment = @team.segments.create!(name: "Never connected", rules: {
      "type" => "group", "combinator" => "and",
      "rules" => [{"type" => "rule", "field" => "custom_attributes.tokens_count", "operator" => "equals", "value" => 0, "value_type" => "number"}]
    })

    get edit_account_segment_url(segment)
    assert_response :success
    fields = JSON.parse(Nokogiri::HTML(response.body).at("[data-segments-builder-fields-value]")["data-segments-builder-fields-value"])
    field = fields.fetch("Subscriber custom attributes").find { |f| f["key"] == "custom_attributes.tokens_count" }
    assert_equal "number", field["type"]
  end

  test "create accepts a predicate via the virtual setter" do
    post account_team_segments_url(@team), params: {
      segment: {
        name: "Subscribed users",
        natural_language_source: "All subscribed users.",
        predicate: "subscribed = 1"
      }
    }
    assert_response :redirect
    segment = Segment.find_by(name: "Subscribed users")
    assert segment, "segment should be created"
    assert_equal "subscribed = 1", segment.predicate
    assert_equal({"predicate" => "subscribed = 1"}, segment.definition)
  end

  test "create from the visual builder saves the rules and narrows the audience" do
    @team.subscribers.create!(email: "vip@example.com", custom_attributes: {"plan" => "vip"})
    @team.subscribers.create!(email: "free@example.com", custom_attributes: {"plan" => "free"})
    rules = plan_rule("vip")

    post account_team_segments_url(@team), params: {segment: {name: "VIPs", rules: rules.to_json}}

    assert_response :redirect
    segment = @team.segments.find_by!(name: "VIPs")
    assert_equal rules, segment.rules
    assert_equal ["vip@example.com"], segment.applies_to(@team.subscribers).pluck(:email)
  end

  test "update from the visual builder replaces the rules" do
    segment = @team.segments.create!(name: "Plan", rules: plan_rule("vip"))

    patch account_segment_url(segment), params: {segment: {rules: plan_rule("free").to_json}}

    assert_response :redirect
    segment.reload
    assert_equal plan_rule("free"), segment.rules
    assert_includes segment.predicate, "'free'"
  end

  test "update can change the predicate" do
    segment = @team.segments.create!(
      name: "S", natural_language_source: "x",
      definition: {"predicate" => "subscribed = 1"}
    )
    patch account_segment_url(segment), params: {
      segment: {predicate: "subscribed = 0"}
    }
    assert_response :redirect
    segment.reload
    assert_equal "subscribed = 0", segment.predicate
  end

  private

  def plan_rule(plan)
    {"type" => "group", "combinator" => "and", "rules" => [
      {"type" => "rule", "field" => "custom_attributes.plan", "value_type" => "string", "operator" => "equals", "value" => plan}
    ]}
  end
end
