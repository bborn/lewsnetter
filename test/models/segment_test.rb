require "test_helper"

class SegmentTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  test "applies_to with a predicate filters subscribers" do
    @team.subscribers.create!(email: "in@x.com", subscribed: true)
    @team.subscribers.create!(email: "out@x.com", subscribed: false)
    segment = @team.segments.create!(
      name: "Subscribed",
      definition: {"predicate" => "subscribed = 1"}
    )

    result = segment.applies_to(@team.subscribers).pluck(:email)
    assert_equal ["in@x.com"], result
  end

  test "applies_to auto-joins companies when the predicate references companies.custom_attributes" do
    brand_co = @team.companies.create!(
      name: "Destination DC", intercom_id: "co-brand-1",
      custom_attributes: {"tenant_type" => "brand"}
    )
    creator_co = @team.companies.create!(
      name: "Creator Co", intercom_id: "co-creator-1",
      custom_attributes: {"tenant_type" => "creator"}
    )
    @team.companies.create!(
      name: "Unrelated", intercom_id: "co-other-1",
      custom_attributes: {"tenant_type" => "brand"}
    )
    sub_brand = @team.subscribers.create!(email: "brand@x.com", company: brand_co)
    @team.subscribers.create!(email: "creator@x.com", company: creator_co)
    @team.subscribers.create!(email: "lone@x.com") # no company

    segment = @team.segments.create!(
      name: "Brand contacts",
      definition: {
        "predicate" => "json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'"
      }
    )

    matched = segment.applies_to(@team.subscribers).pluck(:email)
    assert_equal [sub_brand.email], matched
  end

  test "applies_to can mix subscriber and companies predicates" do
    brand_co = @team.companies.create!(
      name: "Brand", intercom_id: "co-mix-1",
      custom_attributes: {"tenant_type" => "brand"}
    )
    @team.subscribers.create!(email: "active@x.com", subscribed: true, company: brand_co)
    @team.subscribers.create!(email: "inactive@x.com", subscribed: false, company: brand_co)

    segment = @team.segments.create!(
      name: "Subscribed brand contacts",
      definition: {
        "predicate" => "subscribed = 1 AND json_extract(companies.custom_attributes, '$.tenant_type') = 'brand'"
      }
    )

    matched = segment.applies_to(@team.subscribers).pluck(:email)
    assert_equal ["active@x.com"], matched
  end

  test "validate_predicate accepts companies.<col> references" do
    errs = Segment.validate_predicate("companies.name = 'Acme'")
    assert_equal [], errs
  end

  test "validate_predicate still rejects unknown tables" do
    errs = Segment.validate_predicate("events.name = 'x'")
    assert errs.any? { |e| e.include?("disallowed table") }
  end

  test "applies_to raises InvalidPredicate on a forbidden token" do
    segment = @team.segments.create!(
      name: "Bad",
      definition: {"predicate" => "subscribed = 1; DROP TABLE subscribers"}
    )
    assert_raises(Segment::InvalidPredicate) do
      segment.applies_to(@team.subscribers).to_a
    end
  end

  # ---------------------------------------------------------------------
  # PaperTrail audit-history wiring. The segment's `definition` JSON
  # carries the SQL predicate that selects who gets a campaign — versioning
  # is how we answer "what predicate ran when we sent that?".
  # ---------------------------------------------------------------------
  test "paper_trail records a version on create" do
    segment = @team.segments.create!(name: "Audit", definition: {"predicate" => "subscribed = 1"})
    assert_equal 1, segment.versions.count
    assert_equal "create", segment.versions.last.event
  end

  test "paper_trail records a version on update with the definition diff" do
    segment = @team.segments.create!(name: "Audit", definition: {"predicate" => "subscribed = 1"})
    assert_difference -> { segment.versions.count }, 1 do
      segment.update!(definition: {"predicate" => "subscribed = 1 AND id > 0"})
    end
    v = segment.versions.last
    assert_equal "update", v.event
    changes = parse_paper_trail_changes(v.object_changes)
    assert_includes changes.keys, "definition"
  end

  test "paper_trail ignores updated_at-only saves" do
    segment = @team.segments.create!(name: "Audit", definition: {"predicate" => "subscribed = 1"})
    assert_no_difference -> { segment.versions.count } do
      segment.touch
    end
  end

  test "paper_trail records a version on destroy" do
    # Segment has dependent: :restrict_with_error on campaigns — create a
    # standalone segment with no campaigns so the destroy actually runs.
    segment = @team.segments.create!(name: "Audit", definition: {"predicate" => "subscribed = 1"})
    id = segment.id
    segment.destroy!
    v = PaperTrail::Version.where(item_type: "Segment", item_id: id, event: "destroy").last
    assert_not_nil v
  end

  private

  def parse_paper_trail_changes(raw)
    return raw if raw.is_a?(Hash)
    YAML.safe_load(
      raw,
      permitted_classes: [Time, Date, DateTime, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Symbol]
    )
  end
end
