require "test_helper"

class Account::SuppressionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  test "index renders existing rows + the empty-state for a fresh team" do
    get account_team_suppressions_url(@team)
    assert_response :success
    assert_match(/Suppression list/, response.body)
    assert_match(/Clean slate/, response.body)
  end

  test "index lists suppressions ordered by suppressed_at desc" do
    older = Suppression.create!(team: @team, email: "older@example.com", reason: "complaint",
      suppressed_at: 2.days.ago)
    newer = Suppression.create!(team: @team, email: "newer@example.com", reason: "hard_bounce",
      suppressed_at: 1.hour.ago)

    get account_team_suppressions_url(@team)
    assert_response :success
    assert_match(/older@example.com/, response.body)
    assert_match(/newer@example.com/, response.body)
    assert response.body.index("newer@example.com") < response.body.index("older@example.com"),
      "newer rows render above older ones"
  end

  test "create adds a manual suppression row tagged with the operator user id" do
    assert_difference -> { @team.suppressions.count }, 1 do
      post account_team_suppressions_url(@team), params: {
        suppression: {email: "Manual@example.com", reason: "manual", note: "vendor opt-out"}
      }
    end
    assert_redirected_to account_team_suppressions_url(@team)

    row = @team.suppressions.find_by(email: "manual@example.com")
    assert_not_nil row
    assert_equal "manual", row.reason
    assert_equal "vendor opt-out", row.note
    assert_equal "user:#{@user.id}", row.source
  end

  test "create with a bad email re-renders the index with errors" do
    assert_no_difference -> { @team.suppressions.count } do
      post account_team_suppressions_url(@team), params: {
        suppression: {email: "not-an-email", reason: "manual"}
      }
    end
    assert_response :unprocessable_entity
    assert_match(/is invalid/, response.body)
  end

  test "destroy removes a suppression row" do
    row = Suppression.create!(team: @team, email: "gone@example.com", reason: "manual")

    assert_difference -> { @team.suppressions.count }, -1 do
      delete account_suppression_url(row)
    end
    assert_redirected_to account_team_suppressions_url(@team)
  end

  test "destroy is blocked when the row belongs to another team" do
    other_team = create(:team)
    other_row = Suppression.create!(team: other_team, email: "other@example.com", reason: "manual")

    # current_user has no Team#manage ability on other_team. CanCan refuses
    # the action — exact response shape depends on the BulletTrain handler
    # (redirect to login / 403 / etc); what we assert is the row is intact.
    assert_no_difference -> { Suppression.count } do
      delete account_suppression_url(other_row)
    end
    assert Suppression.exists?(other_row.id), "other team's row must not be destroyed"
  end

  test "index is team-scoped — other teams' rows do not appear" do
    other_team = create(:team)
    Suppression.create!(team: other_team, email: "leak@example.com", reason: "complaint")
    Suppression.create!(team: @team,      email: "ours@example.com",  reason: "manual")

    get account_team_suppressions_url(@team)
    assert_response :success
    assert_match(/ours@example.com/, response.body)
    assert_no_match(/leak@example.com/, response.body)
  end
end
