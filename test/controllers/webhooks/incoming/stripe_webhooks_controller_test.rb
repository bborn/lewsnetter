require "test_helper"

class Webhooks::Incoming::StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_secret"

  setup do
    @previous_secret = ENV["STRIPE_WEBHOOKS_ENDPOINT_SECRET"]
    ENV["STRIPE_WEBHOOKS_ENDPOINT_SECRET"] = SECRET
    @payload = {id: "evt_test", object: "event", type: "customer.updated", data: {object: {}}}.to_json
  end

  teardown do
    ENV["STRIPE_WEBHOOKS_ENDPOINT_SECRET"] = @previous_secret
  end

  test "a payload signed with another secret is rejected with 400 and not stored" do
    assert_no_difference -> { Webhooks::Incoming::StripeWebhook.count } do
      post_webhook(@payload, signature_for(@payload, "whsec_some_other_endpoint"))
    end
    assert_response :bad_request
  end

  test "a request without a signature is rejected with 400" do
    assert_no_difference -> { Webhooks::Incoming::StripeWebhook.count } do
      post_webhook(@payload, nil)
    end
    assert_response :bad_request
  end

  test "a correctly signed payload is stored" do
    assert_difference -> { Webhooks::Incoming::StripeWebhook.count }, 1 do
      post_webhook(@payload, signature_for(@payload, SECRET))
    end
    assert_response :created
  end

  private

  def signature_for(payload, secret)
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)
    Stripe::Webhook::Signature.generate_header(timestamp, signature)
  end

  def post_webhook(payload, signature)
    headers = {"CONTENT_TYPE" => "application/json"}
    headers["HTTP_STRIPE_SIGNATURE"] = signature if signature
    post "/webhooks/incoming/stripe_webhooks", params: payload, headers: headers
  end
end
