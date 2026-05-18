require "test_helper"

class SesSenderTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @sender = @team.sender_addresses.create!(
      email: "from@example.com", name: "Sender", verified: true, ses_status: "verified"
    )
    @template = @team.email_templates.create!(
      name: "T", mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
    @campaign = @team.campaigns.create!(
      email_template: @template,
      sender_address: @sender,
      subject: "Hello",
      body_mjml: @template.mjml_body,
      status: "draft"
    )
    @s1 = @team.subscribers.create!(email: "a@example.com", external_id: "ses-a", subscribed: true)
    @s2 = @team.subscribers.create!(email: "b@example.com", external_id: "ses-b", subscribed: true)
  end

  test "returns empty result for empty audience" do
    result = SesSender.send_bulk(campaign: @campaign, subscribers: [])
    assert_equal [], result.message_ids
    assert_equal [], result.failed
  end

  test "stub mode returns one message id per subscriber" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      result = SesSender.send_bulk(campaign: @campaign, subscribers: [@s1, @s2])
      assert_equal 2, result.message_ids.size
      assert_empty result.failed
      assert(result.message_ids.all? { |id| id.start_with?("stub-") })
    ensure
      Rails.application.config.ses_client = original
    end
  end

  test "stub mode records a Delivery row per subscriber with the synthetic id" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      assert_difference -> { Delivery.count }, 2 do
        SesSender.send_bulk(campaign: @campaign, subscribers: [@s1, @s2])
      end

      d1 = Delivery.find_by(subscriber: @s1)
      assert_not_nil d1
      assert_equal "sent", d1.status
      assert_not_nil d1.sent_at
      assert d1.ses_message_id.start_with?("stub-")
      assert_equal @campaign, d1.campaign
    ensure
      Rails.application.config.ses_client = original
    end
  end

  test "render failures record a failed Delivery row" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub

    # Test-only override: swap CampaignRenderer#call to raise. We restore the
    # original alias in ensure so the swap doesn't leak across tests.
    CampaignRenderer.class_eval do
      alias_method :__orig_call_for_test__, :call
      define_method(:call) { raise RuntimeError, "boom" }
    end

    begin
      result = nil
      assert_difference -> { Delivery.count }, 1 do
        result = SesSender.send_bulk(campaign: @campaign, subscribers: [@s1])
      end

      assert_empty result.message_ids
      assert_equal 1, result.failed.size
      delivery = Delivery.find_by(subscriber: @s1)
      assert_equal "failed", delivery.status
      assert_nil delivery.ses_message_id
      assert_includes delivery.error_message, "render_failed"
    ensure
      Rails.application.config.ses_client = original
      CampaignRenderer.class_eval do
        alias_method :call, :__orig_call_for_test__
        remove_method :__orig_call_for_test__
      end
    end
  end

  # Swaps Ses::ClientFor.call to return the provided fake client so we can
  # exercise the non-stub code path without touching AWS. Restored in ensure.
  def with_fake_ses_client(fake_client)
    original_global = Rails.application.config.ses_client
    Rails.application.config.ses_client = nil
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :__orig_call_for_test__, :call
      define_method(:call) { |_team| fake_client }
    end
    yield
  ensure
    Rails.application.config.ses_client = original_global
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :call, :__orig_call_for_test__
      remove_method :__orig_call_for_test__
    end
  end

  test "real SES path records a sent Delivery row with the returned message id" do
    fake_response = Struct.new(:message_id).new("0100ses-real-id-1")
    fake_client = Object.new
    fake_client.define_singleton_method(:send_email) { |**_args| fake_response }

    with_fake_ses_client(fake_client) do
      assert_difference -> { Delivery.count }, 1 do
        result = SesSender.send_bulk(campaign: @campaign, subscribers: [@s1])
        assert_equal ["0100ses-real-id-1"], result.message_ids
      end

      d = Delivery.find_by(ses_message_id: "0100ses-real-id-1")
      assert_not_nil d
      assert_equal "sent", d.status
      assert_equal @s1, d.subscriber
    end
  end

  test "SES rejection records a failed Delivery row with the error message" do
    fake_client = Object.new
    fake_client.define_singleton_method(:send_email) { |**_args| raise StandardError, "SES said no" }

    with_fake_ses_client(fake_client) do
      result = nil
      assert_difference -> { Delivery.count }, 1 do
        result = SesSender.send_bulk(campaign: @campaign, subscribers: [@s1])
      end

      assert_empty result.message_ids
      assert_equal 1, result.failed.size

      d = Delivery.find_by(subscriber: @s1)
      assert_equal "failed", d.status
      assert_nil d.ses_message_id
      assert_equal "SES said no", d.error_message
    end
  end
end
