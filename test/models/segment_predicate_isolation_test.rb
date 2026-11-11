require "test_helper"

# Segment predicates are raw SQL run against the database every team shares.
# A predicate must only ever see its own team's rows: no other tables, and no
# other team's subscribers, companies, events or deliveries, even inside a
# subquery whose result only changes the team's own match count.
class SegmentPredicateIsolationTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @other_team = create(:team)
    @mine = @team.subscribers.create!(email: "mine@example.com", subscribed: true)
    @theirs = @other_team.subscribers.create!(email: "target@other.example", name: "Other Team Target", subscribed: true)
  end

  def matches(predicate)
    @team.segments.create!(name: "probe", definition: {"predicate" => predicate})
      .applies_to(@team.subscribers).count
  end

  # -- reads of tables outside the segment tables are refused -----------------

  test "a subquery against a non-segment table is rejected" do
    errors = Segment.validate_predicate("EXISTS (SELECT 1 FROM users)")
    assert errors.any?, "a predicate must not be able to read the users table"

    assert_raises(Segment::InvalidPredicate) { matches("EXISTS (SELECT 1 FROM users)") }
  end

  test "a credential table is rejected even when quoted" do
    assert Segment.validate_predicate(%{EXISTS (SELECT 1 FROM "oauth_access_tokens")}).any?
    assert Segment.validate_predicate("EXISTS (SELECT 1 FROM `oauth_access_tokens`)").any?
    assert Segment.validate_predicate("EXISTS (SELECT 1 FROM [oauth_access_tokens])").any?
  end

  test "schema and pragma table functions are rejected" do
    assert Segment.validate_predicate("EXISTS (SELECT 1 FROM sqlite_master)").any?
    assert Segment.validate_predicate("EXISTS (SELECT 1 FROM pragma_table_info('users'))").any?
  end

  test "UNION and JOIN inside a subquery are rejected" do
    assert Segment.validate_predicate("id IN (SELECT id FROM subscribers UNION SELECT id FROM users)").any?
    assert Segment.validate_predicate("id IN (SELECT subscriber_id FROM events JOIN users ON 1 = 1)").any?
  end

  test "a comma join in a subquery is rejected" do
    assert Segment.validate_predicate("EXISTS (SELECT 1 FROM events, users)").any?
    assert Segment.validate_predicate("EXISTS (SELECT 1 FROM events, deliveries)").any?
  end

  # -- subqueries on segment tables only see this team's rows -----------------

  test "a subquery on subscribers cannot see another team's subscribers" do
    predicate = "EXISTS (SELECT 1 FROM subscribers WHERE name = 'Other Team Target')"
    assert_empty Segment.validate_predicate(predicate)
    assert_equal 0, matches(predicate), "another team's subscriber must not be visible"
  end

  test "a subquery on companies cannot see another team's companies" do
    @other_team.companies.create!(name: "Other Co", external_id: "other-1")
    assert_equal 0, matches("EXISTS (SELECT 1 FROM companies WHERE name = 'Other Co')")
  end

  test "a subquery on events cannot see another team's events" do
    @other_team.events.create!(subscriber: @theirs, name: "secret_event", occurred_at: Time.current)
    assert_equal 0, matches("EXISTS (SELECT 1 FROM events WHERE name = 'secret_event')")
  end

  test "a subquery on deliveries cannot see another team's deliveries" do
    campaign = create(:campaign, team: @other_team)
    Delivery.create!(campaign: campaign, subscriber: @theirs, ses_message_id: "other-msg")
    assert_equal 0, matches("EXISTS (SELECT 1 FROM deliveries WHERE ses_message_id = 'other-msg')")
  end

  # -- the shapes real segments use keep working ------------------------------

  test "excluding this team's past recipients still works" do
    campaign = create(:campaign, team: @team)
    Delivery.create!(campaign: campaign, subscriber: @mine)
    other = @team.subscribers.create!(email: "fresh@example.com", subscribed: true)

    predicate = "subscribers.id NOT IN (SELECT subscriber_id FROM deliveries WHERE campaign_id IN (#{campaign.id}))"
    assert_empty Segment.validate_predicate(predicate)
    ids = @team.segments.create!(name: "fresh", definition: {"predicate" => predicate})
      .applies_to(@team.subscribers).pluck(:id)
    assert_equal [other.id], ids
  end

  test "a recent-event subquery on this team's events still works" do
    @team.events.create!(subscriber: @mine, name: "campaign_sent", occurred_at: Time.current)
    predicate = "subscribers.subscribed = 1 AND subscribers.id NOT IN " \
      "(SELECT subscriber_id FROM events WHERE name = 'campaign_sent' AND occurred_at >= datetime('now', '-7 days'))"
    assert_empty Segment.validate_predicate(predicate)
    assert_equal 0, matches(predicate)
  end

  test "json, cast and company-attribute predicates still validate" do
    [
      "json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'",
      "CAST(json_extract(custom_attributes, '$.last_active_at') AS INTEGER) >= CAST(strftime('%s','now') AS INTEGER) - 7776000",
      "email_domain NOT IN ('gmail.com','yahoo.com') AND COALESCE(json_extract(custom_attributes, '$.tenant_id'), 0) > 0",
      "EXISTS (SELECT 1 FROM json_each(subscribers.tags) WHERE value = 'vip')",
      "subscribers.created_at >= datetime('now', '-1 days')"
    ].each do |predicate|
      assert_empty Segment.validate_predicate(predicate), predicate
    end
  end

  test "a string literal that looks like a FROM clause is left alone" do
    @team.subscribers.create!(email: "list@example.com", name: "from events list", subscribed: true)
    assert_equal 1, matches("name = 'from events list'")
  end
end
