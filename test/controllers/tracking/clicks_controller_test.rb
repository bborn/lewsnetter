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
end
