require "test_helper"

# Regression tests for B1/B9 (deep QA 2026-05-13):
# Once a subscriber existed, every page that rendered the subscriber row crashed
# with `I18n::MissingInterpolationArgument :subscriber_name` — the destroy
# confirmation locale string referenced `%{subscriber_name}` but `model_locales`
# could not always supply it (e.g. when `label_string.presence` was nil).
#
# These tests guarantee the dashboard, subscribers index, show, edit, and new
# pages all return 200 with at least one subscriber present.
class Account::SubscribersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
    # Create a subscriber so the destroy-confirm interpolation actually runs.
    @subscriber = @team.subscribers.create!(email: "qa-regression@example.com")
  end

  test "team dashboard renders without I18n interpolation crash when subscribers exist" do
    get account_team_url(@team)
    assert_response :success
  end

  test "subscribers index renders without I18n interpolation crash" do
    get account_team_subscribers_url(@team)
    assert_response :success
  end

  test "subscribers show renders without I18n interpolation crash" do
    get account_subscriber_url(@subscriber)
    assert_response :success
  end

  test "subscribers edit renders without I18n interpolation crash" do
    get edit_account_subscriber_url(@subscriber)
    assert_response :success
  end

  test "subscribers new renders" do
    get new_account_team_subscriber_url(@team)
    assert_response :success
  end

  # Belt-and-suspenders: the destroy confirmation string must only reference
  # interpolation variables that model_locales reliably supplies (team_name).
  test "destroy confirmation locale only references team_name interpolation" do
    string = I18n.t("subscribers.buttons.confirmations.destroy",
      team_name: @team.name, teams_possessive: "#{@team.name}'s")
    assert_match @team.name, string
    refute_match(/%\{/, string, "locale string still has unresolved interpolation")
  end
end
