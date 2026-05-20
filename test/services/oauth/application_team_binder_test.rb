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
  # from_authorization_request — the Doorkeeper-hook entry point. Extracts
  # the application (by client_id) + resource owner from the authorizations
  # controller, then binds.
  # ---------------------------------------------------------------------
  test "from_authorization_request binds via client_id + current_resource_owner" do
    controller = stub_controller(client_id: @application.uid, owner: @user)

    Oauth::ApplicationTeamBinder.from_authorization_request(controller)

    assert_equal @team, @application.reload.team
  end

  test "from_authorization_request is a no-op when client_id is missing" do
    controller = stub_controller(client_id: nil, owner: @user)

    assert_nothing_raised do
      Oauth::ApplicationTeamBinder.from_authorization_request(controller)
    end
  end

  test "from_authorization_request swallows errors so the OAuth grant survives" do
    # A controller whose current_resource_owner blows up must not break auth.
    controller = Class.new do
      def initialize(uid) = (@uid = uid)

      def params = ActionController::Parameters.new(client_id: @uid)

      private

      def current_resource_owner = raise("boom")
    end.new(@application.uid)

    assert_nothing_raised do
      Oauth::ApplicationTeamBinder.from_authorization_request(controller)
    end
  end

  private

  def stub_controller(client_id:, owner:)
    Class.new do
      def initialize(client_id, owner)
        @client_id = client_id
        @owner = owner
      end

      def params
        ActionController::Parameters.new(client_id: @client_id)
      end

      private

      def current_resource_owner
        @owner
      end
    end.new(client_id, owner)
  end
end
