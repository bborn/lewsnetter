require "test_helper"

class Account::Campaigns::DeliveriesControllerTest < ActionDispatch::IntegrationTest
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
      subject: "Recipients drill-down test",
      body_mjml: @template.mjml_body,
      status: "sent",
      sent_at: 1.hour.ago
    )

    # Mix of states so filters have something to chew on.
    @opener = @team.subscribers.create!(email: "opener@example.com", external_id: "rd-opener", subscribed: true, name: "Olivia Open")
    @clicker = @team.subscribers.create!(email: "clicker@example.com", external_id: "rd-clicker", subscribed: true, name: "Cleo Click")
    @bouncer = @team.subscribers.create!(email: "bouncer@example.com", external_id: "rd-bouncer", subscribed: true, name: "Boris Bounce")
    @unsub = @team.subscribers.create!(email: "unsub@example.com", external_id: "rd-unsub", subscribed: false, name: "Una Unsub")
    @plain = @team.subscribers.create!(email: "plain@example.com", external_id: "rd-plain", subscribed: true, name: "Patty Plain")

    Delivery.create!(campaign: @campaign, subscriber: @opener, ses_message_id: "rd-1",
      sent_at: 50.minutes.ago, delivered_at: 49.minutes.ago, opened_at: 40.minutes.ago,
      status: "delivered")
    Delivery.create!(campaign: @campaign, subscriber: @clicker, ses_message_id: "rd-2",
      sent_at: 50.minutes.ago, delivered_at: 49.minutes.ago,
      opened_at: 45.minutes.ago, clicked_at: 30.minutes.ago,
      click_count: 3, last_clicked_url: "https://example.com/cta", status: "delivered")
    Delivery.create!(campaign: @campaign, subscriber: @bouncer, ses_message_id: "rd-3",
      sent_at: 50.minutes.ago, bounced_at: 48.minutes.ago,
      bounce_subtype: "MailboxFull", status: "bounced")
    Delivery.create!(campaign: @campaign, subscriber: @unsub, ses_message_id: "rd-4",
      sent_at: 50.minutes.ago, delivered_at: 49.minutes.ago,
      unsubscribed_at: 20.minutes.ago, status: "delivered")
    Delivery.create!(campaign: @campaign, subscriber: @plain, ses_message_id: "rd-5",
      sent_at: 50.minutes.ago, delivered_at: 49.minutes.ago, status: "delivered")
  end

  test "index without a status returns all deliveries" do
    get account_campaign_deliveries_url(@campaign)
    assert_response :success
    # The body contains every recipient email.
    %w[opener clicker bouncer unsub plain].each do |handle|
      assert_match(/#{handle}@example.com/, response.body)
    end
  end

  test "index filters to opened recipients" do
    get account_campaign_deliveries_url(@campaign, status: "opened")
    assert_response :success
    # opener + clicker have opened_at set; bouncer/unsub/plain do not.
    assert_match(/opener@example.com/, response.body)
    assert_match(/clicker@example.com/, response.body)
    refute_match(/bouncer@example.com/, response.body)
    refute_match(/plain@example.com/, response.body)
  end

  test "index filters to clicked recipients" do
    get account_campaign_deliveries_url(@campaign, status: "clicked")
    assert_response :success
    assert_match(/clicker@example.com/, response.body)
    refute_match(/opener@example.com/, response.body)
    refute_match(/plain@example.com/, response.body)
  end

  test "index filters to bounced recipients and shows the bounce subtype" do
    get account_campaign_deliveries_url(@campaign, status: "bounced")
    assert_response :success
    assert_match(/bouncer@example.com/, response.body)
    assert_match(/Mailbox full/i, response.body) # bounce_subtype humanized
    refute_match(/opener@example.com/, response.body)
  end

  test "index filters to unsubscribed recipients" do
    get account_campaign_deliveries_url(@campaign, status: "unsubscribed")
    assert_response :success
    assert_match(/unsub@example.com/, response.body)
    refute_match(/opener@example.com/, response.body)
  end

  test "index rejects an unknown status by falling back to all" do
    get account_campaign_deliveries_url(@campaign, status: "nonsense-bogus-value")
    assert_response :success
    # Should NOT be empty — bogus status falls back to "all".
    assert_match(/opener@example.com/, response.body)
    assert_match(/plain@example.com/, response.body)
  end

  test "csv export returns one row per delivery plus a header row" do
    get account_campaign_deliveries_url(@campaign, format: :csv)
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=" + response.charset

    rows = CSV.parse(response.body)
    # 1 header + 5 deliveries
    assert_equal 6, rows.size

    header = rows.first
    %w[subscriber_email subscriber_name subscriber_external_id status sent_at
      delivered_at opened_at clicked_at bounced_at bounce_subtype
      complained_at unsubscribed_at click_count last_clicked_url].each do |col|
      assert_includes header, col, "expected #{col} in CSV header, got #{header.inspect}"
    end

    body_rows = rows[1..]
    emails = body_rows.map { |r| r[0] }
    %w[opener clicker bouncer unsub plain].each do |h|
      assert_includes emails, "#{h}@example.com"
    end

    # The clicker row should carry click_count=3 + the last_clicked_url.
    clicker_row = body_rows.find { |r| r[0] == "clicker@example.com" }
    assert_equal "3", clicker_row[12]
    assert_equal "https://example.com/cta", clicker_row[13]
  end

  test "csv export ignores status filter (always exports everything)" do
    get account_campaign_deliveries_url(@campaign, format: :csv, status: "opened")
    rows = CSV.parse(response.body)
    # Still 1 header + 5 rows — CSV is the FULL export, not the filtered view.
    assert_equal 6, rows.size
  end

  test "index is forbidden for a user who doesn't belong to the team" do
    other_user = FactoryBot.create(:onboarded_user)
    sign_in other_user

    # BulletTrain's base controller rescues CanCan::AccessDenied and
    # redirects to /account/teams with an alert, so we assert the
    # redirect + the flash rather than expecting a raised exception.
    get account_campaign_deliveries_url(@campaign)
    assert_response :redirect
    assert_match(/not authorized|access denied|cannot/i, flash[:alert].to_s)
    # Body must NOT have leaked any team data.
    follow_redirect!
    refute_match(/opener@example.com/, response.body)
  end

  test "csv attachment Content-Disposition includes a filename" do
    get account_campaign_deliveries_url(@campaign, format: :csv)
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/campaign-#{@campaign.id}-deliveries-.+\.csv/, response.headers["Content-Disposition"])
  end
end
