require "test_helper"

class Tracking::ClicksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @team = create(:team)
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
      status: "sent",
      sent_at: 1.hour.ago
    )
    @subscriber = @team.subscribers.create!(
      email: "alice@example.com", external_id: "click-1", subscribed: true
    )
    @delivery = Delivery.create!(
      campaign: @campaign, subscriber: @subscriber,
      status: "sent", ses_message_id: "ses-click-1", sent_at: 1.hour.ago
    )
    @destination = "https://example.com/promo?utm_source=lewsnetter"
  end

  test "valid token redirects to the original URL and records the click" do
    token = @delivery.signed_click_token(url: @destination)
    assert_nil @delivery.clicked_at
    assert_equal 0, @delivery.click_count

    get "/track/c/#{token}"

    assert_redirected_to @destination
    assert_equal 302, response.status, "must be 302 so every click is re-tracked"

    @delivery.reload
    assert_not_nil @delivery.clicked_at
    assert_equal 1, @delivery.click_count
    assert_equal @destination, @delivery.last_clicked_url
  end

  test "second click bumps click_count but does NOT overwrite clicked_at" do
    first_click = 1.day.ago
    @delivery.update!(clicked_at: first_click, click_count: 1, last_clicked_url: "https://example.com/old")

    token = @delivery.signed_click_token(url: @destination)
    get "/track/c/#{token}"

    @delivery.reload
    assert_in_delta first_click, @delivery.clicked_at, 1.second,
      "first-click timestamp must be preserved on subsequent clicks"
    assert_equal 2, @delivery.click_count
    assert_equal @destination, @delivery.last_clicked_url
  end

  test "malformed token redirects to root URL without crashing" do
    get "/track/c/not-a-real-token"
    assert_redirected_to root_url
  end

  test "valid signature for a deleted delivery redirects to root" do
    token = @delivery.signed_click_token(url: @destination)
    @delivery.destroy!

    get "/track/c/#{token}"
    assert_redirected_to root_url
  end

  test "destination URL can be on an external host" do
    token = @delivery.signed_click_token(url: "https://external.example.org/landing")
    get "/track/c/#{token}"
    assert_response :redirect
    assert_match(/external\.example\.org/, response.location)
  end

  test "resolves the token when the request arrives on a branded host" do
    # When a team configures a branded email subdomain, click links are hosted
    # on that host. The controller resolves the delivery + destination from the
    # signed token, so a request on the branded Host header must still record
    # the click and redirect correctly.
    token = @delivery.signed_click_token(url: @destination)

    get "/track/c/#{token}", headers: {"HTTP_HOST" => "email.influencekit.com"}

    assert_redirected_to @destination
    @delivery.reload
    assert_not_nil @delivery.clicked_at
    assert_equal 1, @delivery.click_count
    assert_equal @destination, @delivery.last_clicked_url
  end

  # ----- ClickEvent rows (human vs machine) -----

  BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

  test "a browser click well after delivery records a human ClickEvent" do
    token = @delivery.signed_click_token(url: @destination)
    get "/track/c/#{token}", headers: {"User-Agent" => BROWSER_UA, "REMOTE_ADDR" => "203.0.113.77"}

    event = @delivery.click_events.sole
    assert_not event.automated
    assert_nil event.automated_reason
    assert_equal @destination, event.url
    assert_equal "GET", event.http_method
    assert_equal "203.0.113.0", event.ip_prefix, "IP must be stored as an anonymized /24"
  end

  test "a scanner user agent is recorded as automated but still redirects" do
    token = @delivery.signed_click_token(url: @destination)
    get "/track/c/#{token}", headers: {"User-Agent" => "Mozilla/5.0 (compatible; Barracuda Sentinel)"}

    assert_redirected_to @destination
    assert_equal "scanner_user_agent", @delivery.click_events.sole.automated_reason
  end

  test "a HEAD request is recorded as automated" do
    token = @delivery.signed_click_token(url: @destination)
    head "/track/c/#{token}", headers: {"User-Agent" => BROWSER_UA}

    assert_equal "head_request", @delivery.click_events.sole.automated_reason
  end

  test "a honeypot hit returns an empty 200, records a honeypot event and leaves raw counters alone" do
    token = @delivery.signed_click_token(url: nil, honeypot: true)
    get "/track/c/#{token}", headers: {"User-Agent" => BROWSER_UA}

    assert_response :ok
    assert_empty response.body
    event = @delivery.click_events.sole
    assert event.honeypot
    assert_equal "honeypot", event.automated_reason
    @delivery.reload
    assert_nil @delivery.clicked_at
    assert_equal 0, @delivery.click_count
  end

  test "a honeypot hit flags the delivery's link clicks in the same burst" do
    get "/track/c/#{@delivery.signed_click_token(url: @destination)}", headers: {"User-Agent" => BROWSER_UA}
    get "/track/c/#{@delivery.signed_click_token(url: nil, honeypot: true)}", headers: {"User-Agent" => BROWSER_UA}

    link_click = @delivery.click_events.links.sole
    assert link_click.automated
    assert_equal "honeypot_burst", link_click.automated_reason
  end
end
