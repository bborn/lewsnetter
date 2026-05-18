require "test_helper"

class Webhooks::Ses::SnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @team = create(:team)
    @bounce_topic = "arn:aws:sns:us-east-1:123:bounce"
    @complaint_topic = "arn:aws:sns:us-east-1:123:complaint"

    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "secret",
      sns_bounce_topic_arn: @bounce_topic,
      sns_complaint_topic_arn: @complaint_topic,
      status: "verified"
    )

    @subscriber = @team.subscribers.create!(
      email: "victim@example.com", external_id: "v1", subscribed: true
    )
  end

  test "permanent bounce unsubscribes the matching subscriber" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "notificationType" => "Bounce",
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal false, @subscriber.subscribed
    assert_not_nil @subscriber.bounced_at
  end

  test "transient bounce does not unsubscribe" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "notificationType" => "Bounce",
        "bounce" => {
          "bounceType" => "Transient",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal true, @subscriber.subscribed
    assert_nil @subscriber.bounced_at
  end

  test "complaint unsubscribes and records complained_at" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @complaint_topic,
      "Message" => {
        "notificationType" => "Complaint",
        "complaint" => {
          "complainedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal false, @subscriber.subscribed
    assert_not_nil @subscriber.complained_at
  end

  test "unknown topic ARN is ignored without erroring" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => "arn:aws:sns:us-east-1:999:unknown",
      "Message" => {
        "notificationType" => "Bounce",
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal true, @subscriber.subscribed
  end

  test "SubscriptionConfirmation returns 200 (subscribe URL is not actually fetched here)" do
    payload = {
      "Type" => "SubscriptionConfirmation",
      "TopicArn" => @bounce_topic,
      "SubscribeURL" => "http://example.invalid/confirm-token"
    }

    # Net::HTTP will fail to resolve example.invalid; the controller swallows
    # the error and still returns 200.
    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok
  end

  test "malformed JSON body returns 400" do
    post "/webhooks/ses/sns", params: "not json at all", headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :bad_request
  end

  test "unknown payload type returns 400" do
    payload = {"Type" => "Mystery", "TopicArn" => @bounce_topic}
    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :bad_request
  end

  test "Event Publishing shape (eventType) — permanent bounce unsubscribes the subscriber" do
    # SES configuration set → SNS event destinations emit `eventType`,
    # not `notificationType`. This is the shape that hits production.
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {"destination" => ["victim@example.com"]},
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal false, @subscriber.subscribed
    assert_not_nil @subscriber.bounced_at
  end

  test "Event Publishing shape — Reject unsubscribes recipients listed in mail.destination" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Reject",
        "mail" => {"destination" => ["victim@example.com"]},
        "reject" => {"reason" => "Bad content"}
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal false, @subscriber.subscribed
    assert_not_nil @subscriber.bounced_at
  end

  # ----- Delivery-row updates (per-recipient stats) -----

  def make_delivery(ses_message_id:, status: "sent", **extras)
    sender = @team.sender_addresses.create!(
      email: "from-#{ses_message_id}@example.com", verified: true, ses_status: "verified"
    )
    campaign = @team.campaigns.create!(
      sender_address: sender,
      subject: "S",
      body_markdown: "Hi",
      status: "sent"
    )
    Delivery.create!(
      campaign: campaign,
      subscriber: @subscriber,
      ses_message_id: ses_message_id,
      sent_at: 1.minute.ago,
      status: status,
      **extras
    )
  end

  test "Event Publishing Bounce updates the matching Delivery row" do
    delivery = make_delivery(ses_message_id: "msg-bounce-1")
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {"messageId" => "msg-bounce-1", "destination" => ["victim@example.com"]},
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    delivery.reload
    assert_equal "bounced", delivery.status
    assert_not_nil delivery.bounced_at
    assert_equal "Permanent", delivery.bounce_subtype
  end

  test "Event Publishing Complaint updates the matching Delivery row" do
    delivery = make_delivery(ses_message_id: "msg-complaint-1")
    payload = {
      "Type" => "Notification",
      "TopicArn" => @complaint_topic,
      "Message" => {
        "eventType" => "Complaint",
        "mail" => {"messageId" => "msg-complaint-1"},
        "complaint" => {
          "complainedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    delivery.reload
    assert_equal "complained", delivery.status
    assert_not_nil delivery.complained_at
  end

  test "Event Publishing Delivery promotes a sent Delivery row to delivered" do
    delivery = make_delivery(ses_message_id: "msg-deliv-1")
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Delivery",
        "mail" => {"messageId" => "msg-deliv-1"},
        "delivery" => {"timestamp" => Time.current.iso8601}
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    delivery.reload
    assert_equal "delivered", delivery.status
    assert_not_nil delivery.delivered_at
  end

  test "Delivery event arriving after Bounce does NOT clobber the bounced status" do
    delivery = make_delivery(ses_message_id: "msg-late-deliv", status: "bounced", bounced_at: 1.minute.ago)
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Delivery",
        "mail" => {"messageId" => "msg-late-deliv"},
        "delivery" => {"timestamp" => Time.current.iso8601}
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    delivery.reload
    assert_equal "bounced", delivery.status, "status must remain bounced after a late Delivery event"
    assert_not_nil delivery.delivered_at, "but delivered_at should still be stamped"
  end

  test "Event Publishing Reject marks the Delivery row failed with the reason" do
    delivery = make_delivery(ses_message_id: "msg-reject-1")
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Reject",
        "mail" => {"messageId" => "msg-reject-1", "destination" => ["victim@example.com"]},
        "reject" => {"reason" => "Bad content"}
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    delivery.reload
    assert_equal "failed", delivery.status
    assert_includes delivery.error_message, "Bad content"
  end

  test "bounce with unknown message_id still updates the subscriber and 200s" do
    # No matching delivery row at all — webhook still flips the subscriber.
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {"messageId" => "msg-from-before-rollout"},
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    @subscriber.reload
    assert_equal false, @subscriber.subscribed
    assert_not_nil @subscriber.bounced_at
  end

  test "cross-tenant routing — a bounce on team A's topic does not unsubscribe team B's subscriber" do
    other_team = create(:team)
    other_team.subscribers.create!(email: "victim@example.com", external_id: "ov", subscribed: true)

    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "notificationType" => "Bounce",
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    other = other_team.subscribers.find_by(email: "victim@example.com")
    assert_equal true, other.subscribed, "Other team's subscriber must not be affected"
  end
end
