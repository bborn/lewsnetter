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
end
