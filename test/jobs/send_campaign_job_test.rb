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

  test "bumps last_contacted_at + times_contacted for everyone the SES call accepted" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    a = @team.subscribers.find_by(email: "a@example.com")
    b = @team.subscribers.find_by(email: "b@example.com")
    assert_nil a.last_contacted_at
    assert_equal 0, a.times_contacted

    begin
      freeze_time do
        SendCampaignJob.perform_now(@campaign.id)
        a.reload
        b.reload
        assert_equal Time.current.to_i, a.last_contacted_at.to_i
        assert_equal Time.current.to_i, b.last_contacted_at.to_i
        assert_equal 1, a.times_contacted
        assert_equal 1, b.times_contacted
      end
    ensure
      Rails.application.config.ses_client = original
    end

    # Unsubscribed subscriber was never sent to → never bumped.
    c = @team.subscribers.find_by(email: "c@example.com")
    assert_nil c.last_contacted_at
    assert_equal 0, c.times_contacted
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

  test "applies segment predicate to narrow the audience" do
    # Two paying subscribers added; the segment should pick only them and skip
    # the two existing setup subscribers (a@, b@) who have no plan attribute.
    @team.subscribers.create!(
      email: "paying-1@example.com", external_id: "p1", subscribed: true,
      custom_attributes: {plan: "growth"}
    )
    @team.subscribers.create!(
      email: "paying-2@example.com", external_id: "p2", subscribed: true,
      custom_attributes: {plan: "growth"}
    )

    segment = @team.segments.create!(
      name: "Paying",
      definition: {"predicate" => "json_extract(custom_attributes, '$.plan') = 'growth'"}
    )
    @campaign.update!(segment: segment)

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
  end

  test "sends to all subscribed when no segment is attached" do
    assert_nil @campaign.segment

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
  end

  test "fails cleanly when segment predicate contains forbidden tokens" do
    segment = @team.segments.create!(
      name: "Bad",
      definition: {"predicate" => "1 = 1"}
    )
    # Bypass any future model-level validation; we want to test the job's
    # defense-in-depth catch.
    segment.update_column(:definition, {"predicate" => "name = 'x'; DROP TABLE users"})
    @campaign.update!(segment: segment)

    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      SendCampaignJob.perform_now(@campaign.id)
    ensure
      Rails.application.config.ses_client = original
    end

    @campaign.reload
    assert_equal "failed", @campaign.status
    assert @campaign.stats["errors"].is_a?(Array)
    assert(
      @campaign.stats["errors"].any? { |e| e.include?("forbidden token") },
      "Expected stats[errors] to mention forbidden token, got #{@campaign.stats["errors"].inspect}"
    )
  end
end
