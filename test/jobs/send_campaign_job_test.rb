require "test_helper"

class SendCampaignJobTest < ActiveJob::TestCase
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
    @team.subscribers.create!(email: "a@example.com", external_id: "job-a", subscribed: true)
    @team.subscribers.create!(email: "b@example.com", external_id: "job-b", subscribed: true)
    # Unsubscribed subscriber should be excluded.
    @team.subscribers.create!(email: "c@example.com", external_id: "job-c", subscribed: false)
  end

  test "transitions to sent and records stats in stub mode" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      SendCampaignJob.perform_now(@campaign.id)
    ensure
      Rails.application.config.ses_client = original
    end

    @campaign.reload
    assert_equal "sent", @campaign.status
    assert_equal 2, @campaign.stats["sent"]
    assert_equal 0, @campaign.stats["failed"]
    assert_not_nil @campaign.sent_at
  end

  test "skips when campaign is already sent" do
    @campaign.update!(status: "sent", sent_at: 1.hour.ago)
    SendCampaignJob.perform_now(@campaign.id)
    assert_equal "sent", @campaign.reload.status
  end

  test "marks as failed on exception" do
    SesSender.singleton_class.class_eval do
      alias_method :_orig_send_bulk, :send_bulk
      define_method(:send_bulk) { |**| raise "boom" }
    end

    begin
      assert_raises(RuntimeError) { SendCampaignJob.perform_now(@campaign.id) }
    ensure
      SesSender.singleton_class.class_eval do
        alias_method :send_bulk, :_orig_send_bulk
        remove_method :_orig_send_bulk
      end
    end

    assert_equal "failed", @campaign.reload.status
  end
end
