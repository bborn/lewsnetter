require "test_helper"

class Webhooks::Ses::SnsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Existing tests were written before SNS signature verification was
    # required. Skip verification for THIS suite only — the signature gate
    # itself has dedicated tests in
    # Webhooks::Ses::SnsSignatureVerificationTest below.
    Webhooks::Ses::SnsController.skip_signature_verification = true

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

  teardown do
    Webhooks::Ses::SnsController.skip_signature_verification = false
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

  # ----- Suppression auto-add -----

  test "permanent bounce adds a Suppression row for the team" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @bounce_topic,
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {"destination" => ["victim@example.com"]},
        "bounce" => {
          "bounceType" => "Permanent",
          "bounceSubType" => "General",
          "bouncedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    assert_difference -> { @team.suppressions.count }, 1 do
      post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    end
    assert_response :ok

    row = @team.suppressions.find_by(email: "victim@example.com")
    assert_not_nil row
    assert_equal "hard_bounce", row.reason
    assert_equal "General", row.source
  end

  test "transient bounce does NOT add a Suppression row" do
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

    assert_no_difference -> { @team.suppressions.count } do
      post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    end
    assert_response :ok
  end

  test "complaint adds a Suppression row tagged with feedback type" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @complaint_topic,
      "Message" => {
        "eventType" => "Complaint",
        "mail" => {"messageId" => "msg-c"},
        "complaint" => {
          "complaintFeedbackType" => "abuse",
          "complainedRecipients" => [{"emailAddress" => "victim@example.com"}]
        }
      }.to_json
    }

    assert_difference -> { @team.suppressions.count }, 1 do
      post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    end
    assert_response :ok

    row = @team.suppressions.find_by(email: "victim@example.com")
    assert_equal "complaint", row.reason
    assert_equal "abuse", row.source
  end

  test "repeat bounce events do not create duplicate Suppression rows" do
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

    assert_no_difference -> { @team.suppressions.count } do
      post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
      assert_response :ok
    end
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

  # ----- H2: cross-tenant Delivery row pollution ------------------------------

  test "H2 — bounce arriving on Team B's topic does NOT mutate Team A's Delivery row even if ses_message_id matches" do
    # Team A: legit delivery
    team_a_delivery = make_delivery(ses_message_id: "msg-shared-id", status: "sent")
    assert_equal "sent", team_a_delivery.reload.status

    # Team B sets up its own SNS topic (the malicious-tenant scenario).
    team_b = create(:team)
    bad_topic = "arn:aws:sns:us-east-1:999:b-bounce"
    team_b.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "secret",
      sns_bounce_topic_arn: bad_topic,
      sns_complaint_topic_arn: "arn:aws:sns:us-east-1:999:b-complaint",
      status: "verified"
    )

    payload = {
      "Type" => "Notification",
      "TopicArn" => bad_topic, # ← Team B's topic
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {"messageId" => "msg-shared-id", "destination" => ["whoever@example.com"]},
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "whoever@example.com"}]
        }
      }.to_json
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :ok

    team_a_delivery.reload
    assert_equal "sent", team_a_delivery.status, "Team A's Delivery row MUST NOT be flipped to bounced via Team B's topic"
    assert_nil team_a_delivery.bounced_at, "bounced_at must remain unstamped"
    assert_nil team_a_delivery.bounce_subtype
  end
end

# Standalone suite for signature verification — keeps the bypass toggle
# isolated so an accidental missing teardown can't poison the rest of the
# suite into silently accepting unsigned payloads.
class Webhooks::Ses::SnsSignatureVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @team = create(:team)
    @topic = "arn:aws:sns:us-east-1:123:bounce"
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "secret",
      sns_bounce_topic_arn: @topic,
      sns_complaint_topic_arn: "arn:aws:sns:us-east-1:123:complaint",
      status: "verified"
    )
    @subscriber = @team.subscribers.create!(email: "v@example.com", external_id: "v1", subscribed: true)

    # Verification ON (the production default). No skip_signature_verification
    # toggle for this suite.
    Webhooks::Ses::SnsController.skip_signature_verification = false
  end

  test "an unsigned payload is rejected with 400 and has no side effects" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @topic,
      "Message" => {
        "eventType" => "Bounce",
        "mail" => {"destination" => ["v@example.com"]},
        "bounce" => {
          "bounceType" => "Permanent",
          "bouncedRecipients" => [{"emailAddress" => "v@example.com"}]
        }
      }.to_json
    }

    assert_no_difference -> { @team.suppressions.count } do
      post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    end
    assert_response :bad_request
    assert @subscriber.reload.subscribed, "subscriber must not be flipped when signature verification fails"
  end

  test "a payload with a bogus Signature value is rejected with 400" do
    payload = {
      "Type" => "Notification",
      "TopicArn" => @topic,
      "MessageId" => "1",
      "Timestamp" => Time.current.iso8601,
      "Message" => "{}",
      "SignatureVersion" => "1",
      "Signature" => Base64.strict_encode64("definitely not a real signature"),
      "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-bogus.pem"
    }

    post "/webhooks/ses/sns", params: payload.to_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response :bad_request
  end
end
