require "application_system_test_case"

class SegmentBuilderEditTest < ApplicationSystemTestCase
  setup do
    @user = FactoryBot.create(:onboarded_user)
    @team = @user.current_team
    login_as(@user, scope: :user)
  end

  test "renaming a predicate-only segment in the form keeps its predicate" do
    # Segments made by the agent or MCP (segments_create) carry a predicate and no rules.
    segment = @team.segments.create!(name: "Paid", predicate: "json_extract(custom_attributes, '$.plan') = 'paid'")

    visit edit_account_segment_path(segment)
    assert_selector "[data-controller='segments-builder'] [data-segments-builder-target='tree'] *"
    fill_in "Name", with: "Paid customers"
    click_on "Update Segment"
    assert_text "Paid customers"

    segment.reload
    assert_equal "Paid customers", segment.name
    assert_equal "json_extract(custom_attributes, '$.plan') = 'paid'", segment.predicate
  end

  test "editing the builder on a predicate-only segment replaces the predicate with the rules" do
    segment = @team.segments.create!(name: "Paid", predicate: "json_extract(custom_attributes, '$.plan') = 'paid'")

    visit edit_account_segment_path(segment)
    find("[data-segments-builder-target='tree'] input[data-action*='changeValue']").fill_in(with: "acct_42")
    click_on "Update Segment"
    assert_text "Segment was successfully updated"

    segment.reload
    assert_equal "(subscribers.external_id = 'acct_42')", segment.predicate
  end
end
