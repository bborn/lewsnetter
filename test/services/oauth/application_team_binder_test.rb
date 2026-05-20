require "test_helper"

class Oauth::ApplicationTeamBinderTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:onboarded_user)
    @team = @user.current_team
    @application = Platform::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
  end

  test "binds a teamless application to the resource owner's current team" do
    assert_nil @application.team_id

    Oauth::ApplicationTeamBinder.bind(application: @application, resource_owner: @user)

    assert_equal @team, @application.reload.team
  end

  test "never reassigns an application that already has a team" do
    other_team = FactoryBot.create(:onboarded_user).current_team
    @application.update!(team: other_team)

    Oauth::ApplicationTeamBinder.bind(application: @application, resource_owner: @user)

    assert_equal other_team, @application.reload.team,
      "an application's team must be permanent once set"
  end

  test "no-op when the application is nil" do
    assert_nothing_raised do
      Oauth::ApplicationTeamBinder.bind(application: nil, resource_owner: @user)
    end
  end

  test "no-op when the resource owner has no current team" do
    owner = Struct.new(:current_team).new(nil)

    Oauth::ApplicationTeamBinder.bind(application: @application, resource_owner: owner)

    assert_nil @application.reload.team_id
  end

  test "no-op when the resource owner does not support current_team" do
    assert_nothing_raised do
      Oauth::ApplicationTeamBinder.bind(application: @application, resource_owner: Object.new)
    end
    assert_nil @application.reload.team_id
  end

  # ---------------------------------------------------------------------
  # from_preauthorization — the Doorkeeper-hook entry point. Reads the
  # application + resource owner straight off the PreAuthorization. It must
  # NOT touch the controller: the same hook fires on /oauth/token with a nil
  # context, and calling current_resource_owner there redirects to sign-in
  # and crashes the token exchange.
  # ---------------------------------------------------------------------
  test "from_preauthorization binds the application to the resource owner's team" do
    pre_auth = stub_pre_auth(application: @application, resource_owner: @user)

    Oauth::ApplicationTeamBinder.from_preauthorization(pre_auth)

    assert_equal @team, @application.reload.team
  end

  test "from_preauthorization is a no-op when pre_auth is nil (the /oauth/token path)" do
    assert_nothing_raised do
      Oauth::ApplicationTeamBinder.from_preauthorization(nil)
    end
  end

  test "from_preauthorization swallows errors so the OAuth grant survives" do
    exploding = Object.new
    def exploding.client = raise("boom")

    def exploding.resource_owner = nil

    assert_nothing_raised do
      Oauth::ApplicationTeamBinder.from_preauthorization(exploding)
    end
  end

  private

  # Mimics a Doorkeeper::OAuth::PreAuthorization: it exposes `client`
  # (a Doorkeeper::OAuth::Client, which carries `.application`) and
  # `resource_owner`.
  def stub_pre_auth(application:, resource_owner:)
    client = Struct.new(:application).new(application)
    Struct.new(:client, :resource_owner).new(client, resource_owner)
  end
end
