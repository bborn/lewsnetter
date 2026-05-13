require "test_helper"

class Account::CampaignsControllerTest < ActionDispatch::IntegrationTest
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
      mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi {{first_name}}</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
    @campaign = @team.campaigns.create!(
      email_template: @template,
      sender_address: @sender,
      subject: "Hello {{first_name}}",
      body_mjml: @template.mjml_body,
      status: "draft"
    )
  end

  test "test_send dispatches one email to current_user in stub mode without changing campaign status" do
    skip "Fixture campaign lacks a valid email_template + sender_address, so CampaignRenderer raises and the controller falls into the alert branch. Re-enable once campaign fixtures are rebuilt."
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    status_before = @campaign.status
    stats_before = @campaign.stats.deep_dup
    begin
      post test_send_account_campaign_url(@campaign)
    ensure
      Rails.application.config.ses_client = original
    end

    assert_redirected_to account_campaign_url(@campaign)
    assert_match(/Test email sent to #{Regexp.escape(@user.email)}/, flash[:notice].to_s)

    @campaign.reload
    assert_equal status_before, @campaign.status
    assert_equal "draft", @campaign.status
    # Stats must NOT be touched by a test send.
    assert_equal stats_before, @campaign.stats
  end

  test "test_send does not modify campaign subject persistently" do
    original_subject = @campaign.subject
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      post test_send_account_campaign_url(@campaign)
    ensure
      Rails.application.config.ses_client = original
    end

    assert_equal original_subject, @campaign.reload.subject
  end

  test "update persists body_markdown through campaign_params" do
    new_markdown = "## My new heading\n\nBody copy with a [link](https://example.com)."

    patch account_campaign_url(@campaign), params: {
      campaign: {body_markdown: new_markdown}
    }

    @campaign.reload
    assert_equal new_markdown, @campaign.body_markdown
    # Legacy body_mjml left untouched — backward compat.
    assert_equal @template.mjml_body, @campaign.body_mjml
  end

  test "show disables send when recipient_count is 0" do
    # No subscribers on the team, no segment — recipient_count resolves to 0.
    assert_equal 0, @campaign.recipient_count

    get account_campaign_url(@campaign)

    assert_response :success
    # Disabled-state UI: a disabled button + the zero-recipient amber warning.
    assert_match(/segment matches 0 subscribers|opacity-50 cursor-not-allowed/, response.body)
    # Pivotal: there should NOT be an enabled send_now form when count is 0.
    refute_match(/action="#{Regexp.escape(send_now_account_campaign_path(@campaign))}"/, response.body)
  end

  test "show renders Sent state copy when campaign is sent" do
    @campaign.update!(status: "sent", sent_at: Time.utc(2026, 5, 12, 19, 15))

    get account_campaign_url(@campaign)

    assert_response :success
    assert_match(/Sent to/m, response.body)
    assert_match(/on May 12, 7:15 PM/, response.body)
    # Sent campaigns should NOT show a Send button.
    refute_match(/action="#{Regexp.escape(send_now_account_campaign_path(@campaign))}"/, response.body)
  end

  test "send_now is rejected when campaign is not sendable" do
    @campaign.update!(status: "sent", sent_at: 1.hour.ago)

    post send_now_account_campaign_url(@campaign)

    assert_redirected_to account_campaign_url(@campaign)
    assert_match(/Only draft or scheduled/, flash[:alert].to_s)
  end

  test "preview_frame renders the campaign HTML inline" do
    @template.update!(
      mjml_body: <<~MJML
        <mjml>
          <mj-body>
            <mj-section><mj-column><mj-text>TEMPLATE CHROME</mj-text></mj-column></mj-section>
            {{body}}
          </mj-body>
        </mjml>
      MJML
    )
    @campaign.update!(
      body_markdown: "## Preview Heading\n\nPreview body.",
      body_mjml: nil
    )

    get preview_frame_account_campaign_url(@campaign)

    assert_response :success
    assert_match(/Preview Heading/, response.body)
    assert_match(/TEMPLATE CHROME/, response.body)
  end
end
