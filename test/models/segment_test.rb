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
end
