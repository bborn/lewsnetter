require "test_helper"

class Tracking::OpensControllerTest < ActionDispatch::IntegrationTest
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
      email: "alice@example.com", external_id: "open-1", subscribed: true
    )
    @delivery = Delivery.create!(
      campaign: @campaign, subscriber: @subscriber,
      status: "sent", ses_message_id: "ses-open-1", sent_at: 1.hour.ago
    )
  end

  test "valid token stamps opened_at and returns a 1x1 gif" do
    assert_nil @delivery.opened_at

    get "/track/o/#{@delivery.tracking_token}.gif"

    assert_response :ok
    assert_equal "image/gif", response.media_type
    assert response.body.start_with?("GIF89a"), "expected GIF89a magic bytes"
    assert_equal Tracking::OpensController::TRANSPARENT_GIF.bytesize, response.body.bytesize

    assert_not_nil @delivery.reload.opened_at
    assert_in_delta Time.current, @delivery.opened_at, 5.seconds
  end

  test "second open is idempotent — opened_at is NOT overwritten" do
    first = 2.days.ago
    @delivery.update!(opened_at: first)

    get "/track/o/#{@delivery.tracking_token}.gif"
    assert_response :ok

    assert_in_delta first, @delivery.reload.opened_at, 1.second
  end

  test "invalid token still returns a gif (no leak)" do
    get "/track/o/this-is-not-a-real-token.gif"
    assert_response :ok
    assert_equal "image/gif", response.media_type
    assert response.body.start_with?("GIF89a")
  end

  test "valid signature for a deleted delivery still returns a gif" do
    token = @delivery.tracking_token
    @delivery.destroy!

    get "/track/o/#{token}.gif"
    assert_response :ok
    assert_equal "image/gif", response.media_type
  end

  test "response forbids caching so opens aren't suppressed downstream" do
    get "/track/o/#{@delivery.tracking_token}.gif"
    assert_match(/no-store/, response.headers["Cache-Control"])
    assert_equal "no-cache", response.headers["Pragma"]
  end

  test "resolves the token when the request arrives on a branded host" do
    # When a team configures a branded email subdomain, the open pixel is
    # hosted on that host. The controller resolves everything from the signed
    # token, so a request on the branded Host header must still stamp the open.
    assert_nil @delivery.opened_at

    get "/track/o/#{@delivery.tracking_token}.gif",
      headers: {"HTTP_HOST" => "email.influencekit.com"}

    assert_response :ok
    assert_equal "image/gif", response.media_type
    assert_not_nil @delivery.reload.opened_at,
      "expected the open to be stamped regardless of which host served the pixel"
  end
end
