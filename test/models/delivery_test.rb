require "test_helper"

class DeliveryTest < ActiveSupport::TestCase
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
      status: "draft"
    )
    @subscriber = @team.subscribers.create!(email: "a@example.com", external_id: "del-a", subscribed: true)
  end

  test "is valid with campaign, subscriber, and default status" do
    d = Delivery.new(campaign: @campaign, subscriber: @subscriber)
    assert d.valid?
    assert_equal "sent", d.status
  end

  test "requires status from whitelist" do
    d = Delivery.new(campaign: @campaign, subscriber: @subscriber, status: "nonsense")
    refute d.valid?
    assert_includes d.errors[:status].first, "is not included"
  end

  test "requires a campaign" do
    d = Delivery.new(subscriber: @subscriber)
    refute d.valid?
  end

  test "requires a subscriber" do
    d = Delivery.new(campaign: @campaign)
    refute d.valid?
  end

  test "ses_message_id is unique across deliveries" do
    Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "ses-xyz", sent_at: Time.current)
    other = @team.subscribers.create!(email: "b@example.com", external_id: "del-b", subscribed: true)
    dup = Delivery.new(campaign: @campaign, subscriber: other, ses_message_id: "ses-xyz", sent_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "allows multiple deliveries with nil ses_message_id (stub/failed sends)" do
    a = @team.subscribers.create!(email: "x@example.com", external_id: "del-x", subscribed: true)
    b = @team.subscribers.create!(email: "y@example.com", external_id: "del-y", subscribed: true)
    Delivery.create!(campaign: @campaign, subscriber: a, status: "failed", error_message: "boom")
    assert_nothing_raised do
      Delivery.create!(campaign: @campaign, subscriber: b, status: "failed", error_message: "boom again")
    end
  end

  test "instance predicates reflect the timestamps and status" do
    d = Delivery.new(campaign: @campaign, subscriber: @subscriber)
    refute d.opened?
    refute d.clicked?
    refute d.bounced?
    refute d.complained?
    refute d.delivered?
    refute d.failed?

    d.opened_at = Time.current
    d.clicked_at = Time.current
    d.bounced_at = Time.current
    d.complained_at = Time.current
    d.delivered_at = Time.current
    assert d.opened?
    assert d.clicked?
    assert d.bounced?
    assert d.complained?
    assert d.delivered?

    d2 = Delivery.new(campaign: @campaign, subscriber: @subscriber, status: "failed")
    assert d2.failed?
  end

  test "scopes filter by the appropriate column" do
    s2 = @team.subscribers.create!(email: "c@example.com", external_id: "del-c", subscribed: true)
    s3 = @team.subscribers.create!(email: "d@example.com", external_id: "del-d", subscribed: true)
    s4 = @team.subscribers.create!(email: "e@example.com", external_id: "del-e", subscribed: true)
    s5 = @team.subscribers.create!(email: "f@example.com", external_id: "del-f", subscribed: true)

    sent = Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "m1", sent_at: Time.current)
    delivered = Delivery.create!(campaign: @campaign, subscriber: s2, ses_message_id: "m2", sent_at: Time.current, delivered_at: Time.current, status: "delivered")
    bounced = Delivery.create!(campaign: @campaign, subscriber: s3, ses_message_id: "m3", sent_at: Time.current, bounced_at: Time.current, status: "bounced")
    complained = Delivery.create!(campaign: @campaign, subscriber: s4, ses_message_id: "m4", sent_at: Time.current, complained_at: Time.current, status: "complained")
    failed = Delivery.create!(campaign: @campaign, subscriber: s5, status: "failed", error_message: "x")

    assert_includes Delivery.sent, sent
    assert_includes Delivery.sent, delivered  # delivered has ses_message_id
    refute_includes Delivery.sent, failed     # no ses_message_id

    assert_equal [delivered], Delivery.delivered.to_a
    assert_equal [bounced], Delivery.bounced.to_a
    assert_equal [complained], Delivery.complained.to_a
    assert_equal [failed], Delivery.failed.to_a
    assert_empty Delivery.opened
    assert_empty Delivery.clicked
  end

  test "bounced scope finds rows via either bounced_at or status=bounced" do
    s2 = @team.subscribers.create!(email: "g@example.com", external_id: "del-g", subscribed: true)
    by_ts = Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "ts-1", bounced_at: Time.current, status: "sent")
    by_status = Delivery.create!(campaign: @campaign, subscriber: s2, status: "bounced")
    bounced_ids = Delivery.bounced.pluck(:id)
    assert_includes bounced_ids, by_ts.id
    assert_includes bounced_ids, by_status.id
  end

  test "campaign has_many :deliveries (dependent: :destroy)" do
    Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "destroy-me", sent_at: Time.current)
    assert_equal 1, @campaign.deliveries.count
    assert_difference -> { Delivery.count }, -1 do
      @campaign.destroy!
    end
  end

  test "subscriber has_many :deliveries (dependent: :destroy)" do
    Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "destroy-sub", sent_at: Time.current)
    assert_equal 1, @subscriber.deliveries.count
    assert_difference -> { Delivery.count }, -1 do
      @subscriber.destroy!
    end
  end

  test "tracking_token round-trips through find_by_tracking_token" do
    d = Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "rt-1", sent_at: Time.current)
    token = d.tracking_token
    assert token.present?

    found = Delivery.find_by_tracking_token(token, purpose: :delivery_open)
    assert_equal d, found
  end

  test "find_by_tracking_token returns nil for a bogus token" do
    assert_nil Delivery.find_by_tracking_token("garbage", purpose: :delivery_open)
    assert_nil Delivery.find_by_tracking_token("", purpose: :delivery_open)
  end

  test "find_by_tracking_token rejects a token signed for a different purpose" do
    d = Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "rt-2", sent_at: Time.current)
    other_purpose_token = Rails.application.message_verifier(:something_else).generate(d.id)
    assert_nil Delivery.find_by_tracking_token(other_purpose_token, purpose: :delivery_open)
  end

  test "find_by_tracking_token returns nil if the row was deleted after the token was minted" do
    d = Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "rt-3", sent_at: Time.current)
    token = d.tracking_token
    d.destroy!
    assert_nil Delivery.find_by_tracking_token(token, purpose: :delivery_open)
  end

  test "signed_click_token round-trips delivery id and URL" do
    d = Delivery.create!(campaign: @campaign, subscriber: @subscriber, ses_message_id: "click-rt-1", sent_at: Time.current)
    token = d.signed_click_token(url: "https://example.com/landing")
    payload = Rails.application.message_verifier(:delivery_click).verify(token)
    assert_equal d.id, payload["delivery_id"]
    assert_equal "https://example.com/landing", payload["url"]
  end
end
