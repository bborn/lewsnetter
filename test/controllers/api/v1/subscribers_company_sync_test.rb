require "controllers/api/v1/test"

# Company sync at the api/v1 bulk seam.
#
# Source apps (Intercom-style) carry each subscriber's company inline as a
# `company` block on the subscriber payload. The bulk endpoint find-or-creates
# the Company (keyed on external_id, scoped to the team), merges its custom
# attributes, and links the subscriber — no separate company endpoint needed.
#
# Extends Api::V1::Test (gives @user/@team/access_token) rather than the
# scaffold-generated SubscribersControllerTest, whose setup depends on a
# :subscriber factory this app doesn't define.
class Api::V1::SubscribersCompanySyncTest < Api::V1::Test
  def post_bulk(*rows)
    body = rows.map(&:to_json).join("\n") + "\n"
    post "/api/v1/teams/#{@team.id}/subscribers/bulk",
      params: body,
      headers: {"CONTENT_TYPE" => "application/x-ndjson", "Authorization" => "Bearer #{access_token}"}
  end

  test "bulk upsert creates and links a company from the inline company block" do
    assert_difference -> { @team.companies.count }, 1 do
      post_bulk(
        external_id: "u-100",
        email: "owner@acme.test",
        subscribed: true,
        company: {external_id: "t-100", name: "Acme", attributes: {plan: "pro", tenant_type: "brand", tabs_enabled: "billing,reports"}}
      )
    end
    assert_response :success

    company = @team.subscribers.find_by!(external_id: "u-100").company
    assert_not_nil company
    assert_equal "t-100", company.external_id
    assert_equal "Acme", company.name
    assert_equal "brand", company.custom_attributes["tenant_type"]
    assert_equal "pro", company.custom_attributes["plan"]
    # the generic attribute normalizer applies to company attrs too (CSV -> array)
    assert_equal ["billing", "reports"], company.custom_attributes["tabs_enabled"]
  end

  test "bulk upsert reuses an existing company by external_id and merges attributes" do
    existing = @team.companies.create!(external_id: "t-200", name: "Beta", custom_attributes: {"plan" => "free"})

    assert_no_difference -> { @team.companies.count } do
      post_bulk(
        {external_id: "u-201", email: "a@beta.test", subscribed: true,
         company: {external_id: "t-200", name: "Beta Inc", attributes: {tenant_type: "brand"}}},
        {external_id: "u-202", email: "b@beta.test", subscribed: true,
         company: {external_id: "t-200", attributes: {plan: "pro"}}}
      )
    end
    assert_response :success

    existing.reload
    assert_equal "Beta Inc", existing.name # later name wins; an absent name keeps the prior one
    assert_equal "brand", existing.custom_attributes["tenant_type"]
    assert_equal "pro", existing.custom_attributes["plan"] # merged; prior value overwritten, not dropped
    linked = %w[u-201 u-202].map { |x| @team.subscribers.find_by!(external_id: x).company_id }
    assert_equal [existing.id], linked.uniq
  end

  test "bulk upsert with a company block lacking an external_id leaves the subscriber unlinked" do
    assert_no_difference -> { @team.companies.count } do
      post_bulk(external_id: "u-250", email: "n@example.test", subscribed: true, company: {name: "No ID"})
    end
    assert_response :success
    assert_nil @team.subscribers.find_by!(external_id: "u-250").company_id
  end

  test "bulk upsert without a company block leaves the subscriber unlinked (no regression)" do
    post_bulk(external_id: "u-300", email: "solo@example.test", subscribed: true)
    assert_response :success
    assert_nil @team.subscribers.find_by!(external_id: "u-300").company_id
  end
end
