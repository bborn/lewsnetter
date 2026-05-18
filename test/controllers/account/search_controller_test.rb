require "test_helper"

# Tests the Cmd+K command palette endpoint. Covers:
# - empty-query "recent items" fallback
# - text query across each surface
# - team scoping (other-team rows must not leak)
# - subscriber email exact-match (deterministic-encrypted column)
# - subscriber name LIKE (legacy plaintext via support_unencrypted_data)
class Account::SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  test "empty query returns recent items across surfaces" do
    @team.subscribers.create!(email: "recent@example.com", name: "Recent Person", external_id: "ext-r1")
    @team.segments.create!(name: "Recent segment")
    @team.email_templates.create!(name: "Recent template")
    @team.campaigns.create!(subject: "Recent campaign", body_markdown: "Body")
    @team.sender_addresses.create!(email: "sender@example.com", name: "Sender Brand")
    @team.companies.create!(name: "Recent Co")

    get account_team_search_url(@team, format: :json)
    assert_response :success

    body = JSON.parse(response.body)
    assert_kind_of Hash, body
    labels = body.fetch("groups").map { |g| g["label"] }

    # All six surfaces had a row created above, so all six should appear.
    %w[Subscribers Companies Segments Campaigns Email\ Templates Sender\ Addresses].each do |label|
      assert_includes labels, label, "Expected #{label} group in recent-items response"
    end
  end

  test "search by exact subscriber email finds the row even though email is encrypted" do
    target = @team.subscribers.create!(email: "exact@example.com", name: "Whatever")
    @team.subscribers.create!(email: "other@example.com", name: "Other")

    get account_team_search_url(@team, q: "exact@example.com", format: :json)
    assert_response :success

    body = JSON.parse(response.body)
    sub_group = body["groups"].find { |g| g["type"] == "subscriber" }
    refute_nil sub_group, "Expected a subscriber group"
    urls = sub_group["items"].map { |i| i["url"] }
    assert_includes urls, account_subscriber_path(target)
  end

  test "search by external_id matches subscribers (plaintext column)" do
    target = @team.subscribers.create!(email: "a@example.com", external_id: "user-12345")
    @team.subscribers.create!(email: "b@example.com", external_id: "other-9")

    get account_team_search_url(@team, q: "12345", format: :json)
    assert_response :success

    body = JSON.parse(response.body)
    sub_group = body["groups"].find { |g| g["type"] == "subscriber" }
    refute_nil sub_group
    urls = sub_group["items"].map { |i| i["url"] }
    assert_includes urls, account_subscriber_path(target)
  end

  test "search by campaign subject substring" do
    target = @team.campaigns.create!(subject: "Holiday Newsletter", body_markdown: "Hi")
    @team.campaigns.create!(subject: "Other thing", body_markdown: "Hi")

    get account_team_search_url(@team, q: "holiday", format: :json)
    assert_response :success

    body = JSON.parse(response.body)
    camp_group = body["groups"].find { |g| g["type"] == "campaign" }
    refute_nil camp_group
    urls = camp_group["items"].map { |i| i["url"] }
    assert_includes urls, account_campaign_path(target)
  end

  test "search by segment name OR natural-language source" do
    by_name = @team.segments.create!(name: "Power users", natural_language_source: "x")
    by_nls  = @team.segments.create!(name: "Other", natural_language_source: "everyone with churn signal")

    get account_team_search_url(@team, q: "churn", format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    seg_group = body["groups"].find { |g| g["type"] == "segment" }
    refute_nil seg_group
    urls = seg_group["items"].map { |i| i["url"] }
    assert_includes urls, account_segment_path(by_nls)
    refute_includes urls, account_segment_path(by_name)
  end

  test "search by sender address email" do
    target = @team.sender_addresses.create!(email: "founder@brand.com", name: "Founder")
    @team.sender_addresses.create!(email: "support@brand.com", name: "Support")

    get account_team_search_url(@team, q: "founder", format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    sa_group = body["groups"].find { |g| g["type"] == "sender_address" }
    refute_nil sa_group
    urls = sa_group["items"].map { |i| i["url"] }
    assert_includes urls, account_sender_address_path(target)
  end

  test "search by email template name" do
    target = @team.email_templates.create!(name: "Welcome HTML")
    @team.email_templates.create!(name: "Receipt")

    get account_team_search_url(@team, q: "welcome", format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    tpl_group = body["groups"].find { |g| g["type"] == "email_template" }
    refute_nil tpl_group
    urls = tpl_group["items"].map { |i| i["url"] }
    assert_includes urls, account_email_template_path(target)
  end

  test "search by company name returns subscribers-index URL filtered by company_id" do
    target = @team.companies.create!(name: "Acme Inc", external_id: "acme-1")
    @team.companies.create!(name: "Other Co")

    get account_team_search_url(@team, q: "acme", format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    co_group = body["groups"].find { |g| g["type"] == "company" }
    refute_nil co_group
    urls = co_group["items"].map { |i| i["url"] }
    assert urls.any? { |u| u.include?("company_id=#{target.id}") }, "Expected company URL to filter subscribers by company_id"
  end

  test "results do not leak across teams" do
    other_user = FactoryBot.create(:onboarded_user)
    other_team = other_user.current_team
    other_team.campaigns.create!(subject: "Holiday in another team", body_markdown: "Hi")

    get account_team_search_url(@team, q: "holiday", format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    assert_empty body["groups"], "Expected no results when another team owns the matching row"
  end

  test "requires sign-in" do
    sign_out @user
    get account_team_search_url(@team, format: :json)
    # Devise returns 401 Unauthorized for JSON requests rather than redirecting.
    assert_response :unauthorized
  end

  test "user cannot query a team they don't belong to" do
    other_user = FactoryBot.create(:onboarded_user)
    other_team = other_user.current_team

    get account_team_search_url(other_team, q: "anything", format: :json)
    # Either a 404 (not a member, find fails) or 403 (cancancan denies).
    # Both are acceptable signals — they mean we didn't leak data.
    refute_equal 200, response.status
  end

  test "empty query returns an Actions group with create + navigate rows" do
    get account_team_search_url(@team, format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    actions = body["groups"].find { |g| g["label"] == "Actions" }
    assert actions, "expected Actions group in groups"
    titles = actions["items"].map { |i| i["title"] }
    assert_includes titles, "Create new campaign"
    assert_includes titles, "Subscribers"
    actions["items"].each do |i|
      assert_equal "action", i["type"]
      assert i["url"].to_s.start_with?("/"), "action url should be a path: #{i.inspect}"
    end
  end

  test "actions are filtered by case-insensitive substring on title or subtitle" do
    get account_team_search_url(@team, q: "campaign", format: :json)
    assert_response :success
    actions = JSON.parse(response.body)["groups"].find { |g| g["label"] == "Actions" }
    titles = actions["items"].map { |i| i["title"] }
    assert_includes titles, "Create new campaign"
    assert_includes titles, "Campaigns"
    refute_includes titles, "Team settings"
  end

  test "actions group is the first group so it surfaces above search hits" do
    get account_team_search_url(@team, format: :json)
    assert_response :success
    assert_equal "Actions", JSON.parse(response.body)["groups"].first["label"]
  end
end
