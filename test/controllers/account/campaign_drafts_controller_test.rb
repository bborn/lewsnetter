require "test_helper"

class Account::CampaignDraftsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team

    @sender = @team.sender_addresses.create!(
      email: "from@example.com", name: "Sender", verified: true, ses_status: "verified"
    )
    @template = @team.email_templates.create!(
      name: "T",
      mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
    @campaign = @team.campaigns.create!(
      email_template: @template,
      sender_address: @sender,
      subject: "Hello",
      body_mjml: @template.mjml_body,
      status: "draft"
    )
  end

  test "create responds 200 to a TURBO_STREAM request" do
    AI::Base.force_stub = true
    begin
      post draft_account_campaign_url(@campaign),
        params: {brief: "We just shipped X. Tell our users."},
        as: :turbo_stream
    ensure
      AI::Base.force_stub = false
    end

    assert_response :success
    # The html partial rendered — body should contain something MJML-ish or stub copy.
    assert_match(/mjml|stub mode|preheader|Subject/i, response.body)
  end

  test "create responds 200 to an HTML request (regression baseline)" do
    AI::Base.force_stub = true
    begin
      post draft_account_campaign_url(@campaign),
        params: {brief: "We just shipped X. Tell our users."}
    ensure
      AI::Base.force_stub = false
    end

    assert_response :success
  end

  # The Stimulus `ai-drafter` controller on the campaign edit page POSTs JSON
  # and consumes `{body_markdown, subjects, preheader}` from the response.
  # If this contract breaks, the editor silently fails — exactly the bug
  # Bruno hit before this rebuild. Lock it in.
  test "create responds with JSON when requested as JSON" do
    AI::Base.force_stub = true
    begin
      post draft_account_campaign_url(@campaign),
        params: {brief: "We just shipped X. Tell our users."},
        as: :json
    ensure
      AI::Base.force_stub = false
    end

    assert_response :success
    assert_equal "application/json; charset=utf-8", response.content_type
    payload = JSON.parse(response.body)
    # Field-by-field rather than a shape check — the editor expects these names.
    assert payload.key?("body_markdown"), "JSON draft must include body_markdown"
    assert payload["body_markdown"].present?, "stub draft must produce a non-empty body_markdown"
    assert payload.key?("preheader")
    assert payload.key?("subjects")
    assert_kind_of Array, payload["subjects"]
    assert payload["subjects"].any?, "stub draft must produce at least one subject candidate"
    assert_includes [true, false], payload["stub"]
  end
end
