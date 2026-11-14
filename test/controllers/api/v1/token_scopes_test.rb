require "controllers/api/v1/test"

# The OAuth consent page says mcp:read only reads
# (config/locales/en/doorkeeper.en.yml). A token granted mcp:read without
# mcp:write or admin may only make GET/HEAD requests to /api/v1.
class Api::V1::TokenScopesTest < Api::V1::Test
  setup do
    @campaign = @team.campaigns.create!(subject: "Draft", status: "draft", body_markdown: "Hello")
  end

  test "a read-only token cannot delete a campaign" do
    delete "/api/v1/campaigns/#{@campaign.to_param}", headers: auth(token_with("mcp:read"))

    assert_response :forbidden
    assert Campaign.exists?(@campaign.id)
  end

  test "a read-only token cannot create a segment" do
    assert_no_difference -> { @team.segments.count } do
      post "/api/v1/teams/#{@team.to_param}/segments",
        params: {segment: {name: "Nope"}}.to_json,
        headers: auth(token_with("mcp:read")).merge("CONTENT_TYPE" => "application/json")
    end

    assert_response :forbidden
  end

  test "a read-only token can still read" do
    get "/api/v1/campaigns/#{@campaign.to_param}", headers: auth(token_with("mcp:read"))

    assert_response :success
  end

  test "tokens that may write keep write access" do
    ["read write delete", "admin", "", "mcp:read mcp:write", "admin mcp:read"].each do |scopes|
      campaign = @team.campaigns.create!(subject: "Keep #{scopes}", status: "draft", body_markdown: "Hello")
      delete "/api/v1/campaigns/#{campaign.to_param}", headers: auth(token_with(scopes))

      assert_response :success, "scopes #{scopes.inspect}"
      refute Campaign.exists?(campaign.id), "scopes #{scopes.inspect} lost write access"
    end
  end

  private

  def token_with(scopes)
    Doorkeeper::AccessToken.create!(
      resource_owner_id: @user.id,
      application: @platform_application,
      scopes: scopes,
      token: SecureRandom.hex
    ).token
  end

  def auth(token)
    {"Authorization" => "Bearer #{token}"}
  end
end
