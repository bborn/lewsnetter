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

  test "de-dupes by email so a person with multiple subscriber rows is emailed once" do
    # Same person, synced twice from the source app under different external_ids
    # (the sync keys on external_id, not email — so duplicate source records
    # become duplicate subscriber rows sharing an address). Also a case-variant
    # of b@ to prove the dedupe is case-insensitive.
    @team.subscribers.create!(email: "a@example.com", external_id: "job-a-dupe", subscribed: true)
    @team.subscribers.create!(email: "B@EXAMPLE.COM", external_id: "job-b-dupe", subscribed: true)

    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      SendCampaignJob.perform_now(@campaign.id)
    ensure
      Rails.application.config.ses_client = original
    end

    @campaign.reload
    assert_equal "sent", @campaign.status
    # Audience is 4 subscribed rows but only 2 distinct addresses → 2 sends.
    assert_equal 2, @campaign.stats["sent"]
    assert_equal 2, @campaign.stats["duplicates"]
  end

  test "de-duped rows do not get last_contacted bumped" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    dupe = @team.subscribers.create!(email: "a@example.com", external_id: "job-a-dupe2", subscribed: true)

    begin
      SendCampaignJob.perform_now(@campaign.id)
    ensure
      Rails.application.config.ses_client = original
    end

    # The winning (oldest) row for a@ was contacted; the duplicate row was not.
    winner = @team.subscribers.where(email: "a@example.com").order(:id).first
    assert_not_nil winner.reload.last_contacted_at
    assert_nil dupe.reload.last_contacted_at
    assert_equal 0, dupe.times_contacted
  end

  test "skips when campaign is already sent" do
    @campaign.update!(status: "sent", sent_at: 1.hour.ago)
    SendCampaignJob.perform_now(@campaign.id)
    assert_equal "sent", @campaign.reload.status
  end

  test "a worker with a stale draft cannot send a campaign already claimed by another worker" do
    original_client = Rails.application.config.ses_client
    original_find = Campaign.method(:find)
    id = @campaign.id
    stale = original_find.call(id)
    Rails.application.config.ses_client = :stub

    SendCampaignJob.perform_now(id)
    assert_equal "sent", @campaign.reload.status
    assert_equal "draft", stale.status
    assert_equal 2, @campaign.deliveries.count

    Campaign.define_singleton_method(:find) do |*ids|
      (ids == [id]) ? stale : original_find.call(*ids)
    end

    assert_no_difference -> { @campaign.deliveries.count } do
      SendCampaignJob.perform_now(id)
    end
    assert_equal "sent", @campaign.reload.status
  ensure
    Campaign.define_singleton_method(:find, original_find)
    Rails.application.config.ses_client = original_client
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

  # --- Resend safety -------------------------------------------------------

  def with_stub_ses
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    yield
  ensure
    Rails.application.config.ses_client = original
  end

  def subscriber(email)
    @team.subscribers.find_by!(email: email)
  end

  test "never mails a subscriber who already has a delivery for the campaign" do
    a = subscriber("a@example.com")
    @campaign.deliveries.create!(subscriber: a, status: "sent", ses_message_id: "earlier-run", sent_at: 1.hour.ago)

    with_stub_ses { SendCampaignJob.perform_now(@campaign.id) }

    assert_equal "sent", @campaign.reload.status
    assert_equal 1, @campaign.deliveries.where(subscriber: a).count
    assert_equal ["earlier-run"], @campaign.deliveries.where(subscriber: a).pluck(:ses_message_id)
    assert_equal 1, @campaign.deliveries.where(subscriber: subscriber("b@example.com")).count
    assert_nil a.reload.last_contacted_at
  end

  test "resuming a failed send only mails subscribers who weren't sent to" do
    a = subscriber("a@example.com")
    @campaign.deliveries.create!(subscriber: a, status: "sent", ses_message_id: "first-run", sent_at: 1.hour.ago)
    @campaign.update!(status: "sending")
    @campaign.update!(status: "failed", stats: {"sent" => 1, "failed" => 0, "suppressed" => 0, "duplicates" => 0, "errors" => ["boom"]})

    with_stub_ses { SendCampaignJob.perform_now(@campaign.id, resume: true) }

    @campaign.reload
    assert_equal "sent", @campaign.status
    assert_equal 2, @campaign.deliveries.count
    assert_equal 1, @campaign.deliveries.where(subscriber: a).count
    # Counters carry on from the interrupted run.
    assert_equal 2, @campaign.stats["sent"]
  end

  test "resume also skips another subscriber row sharing an address already sent to" do
    a = subscriber("a@example.com")
    twin = @team.subscribers.create!(email: "A@example.com", external_id: "job-a-twin", subscribed: true)
    @campaign.deliveries.create!(subscriber: a, status: "sent", ses_message_id: "first-run", sent_at: 1.hour.ago)
    @campaign.update!(status: "sending")
    @campaign.update!(status: "failed")

    with_stub_ses { SendCampaignJob.perform_now(@campaign.id, resume: true) }

    assert_equal 0, @campaign.deliveries.where(subscriber: twin).count
    assert_equal 2, @campaign.deliveries.count
  end

  test "resume picks up a campaign stuck in sending after its worker died" do
    a = subscriber("a@example.com")
    @campaign.update!(status: "sending")
    delivery = @campaign.deliveries.create!(subscriber: a, status: "sent", ses_message_id: "first-run", sent_at: 1.hour.ago)
    delivery.update_columns(created_at: 1.hour.ago)
    @campaign.update_columns(updated_at: 1.hour.ago)

    with_stub_ses { SendCampaignJob.perform_now(@campaign.id, resume: true) }

    assert_equal "sent", @campaign.reload.status
    assert_equal 2, @campaign.deliveries.count
  end

  test "resume leaves a campaign that is still actively sending alone" do
    @campaign.update!(status: "sending")

    assert_no_difference -> { Delivery.count } do
      with_stub_ses { SendCampaignJob.perform_now(@campaign.id, resume: true) }
    end
    assert_equal "sending", @campaign.reload.status
  end

  test "resume does nothing for draft or sent campaigns" do
    assert_no_difference -> { Delivery.count } do
      with_stub_ses { SendCampaignJob.perform_now(@campaign.id, resume: true) }
    end
    assert_equal "draft", @campaign.reload.status
  end

  # --- Scheduled dispatch revalidation --------------------------------------

  test "a scheduler-enqueued job skips when scheduled_for was moved to the future" do
    @campaign.update!(
      status: "scheduled",
      scheduled_for: 5.minutes.ago,
      all_subscribers_confirmed: true
    )

    assert_no_difference -> { Delivery.count } do
      with_stub_ses do
        @campaign.update!(scheduled_for: 1.day.from_now)
        SendCampaignJob.perform_now(@campaign.id, from_scheduler: true)
      end
    end

    @campaign.reload
    assert_equal "scheduled", @campaign.status
    assert @campaign.scheduled_for > Time.current
  end

  test "a scheduler-enqueued job skips when the campaign was cancelled back to draft" do
    @campaign.update!(
      status: "scheduled",
      scheduled_for: 5.minutes.ago,
      all_subscribers_confirmed: true
    )

    assert_no_difference -> { Delivery.count } do
      with_stub_ses do
        @campaign.update!(status: "draft", scheduled_for: nil)
        SendCampaignJob.perform_now(@campaign.id, from_scheduler: true)
      end
    end

    assert_equal "draft", @campaign.reload.status
  end

  test "a scheduler-enqueued job skips when the segment was removed without all-subscribers confirmation" do
    segment = @team.segments.create!(
      name: "Only B",
      definition: {"predicate" => "email = 'b@example.com'"}
    )
    @campaign.update!(
      status: "scheduled",
      scheduled_for: 5.minutes.ago,
      segment: segment,
      all_subscribers_confirmed: false
    )

    assert_no_difference -> { Delivery.count } do
      with_stub_ses do
        @campaign.update!(segment: nil)
        SendCampaignJob.perform_now(@campaign.id, from_scheduler: true)
      end
    end

    @campaign.reload
    assert_equal "scheduled", @campaign.status
    assert_nil @campaign.segment_id
  end

  test "a manual send still works for a due scheduled campaign" do
    @campaign.update!(
      status: "scheduled",
      scheduled_for: 5.minutes.ago,
      all_subscribers_confirmed: true
    )

    with_stub_ses { SendCampaignJob.perform_now(@campaign.id) }

    assert_equal "sent", @campaign.reload.status
    assert_equal 2, @campaign.stats["sent"]
  end

  test "does not bump contact counters for a recipient another run delivered mid-send" do
    a = subscriber("a@example.com")
    b = subscriber("b@example.com")
    contacted_at = 2.hours.ago.change(usec: 0)
    a.update!(last_contacted_at: contacted_at, times_contacted: 5)

    # Another run inserts a's Delivery after this run read its audience, so
    # SesSender hits the unique index and reports a as already_delivered.
    campaign = @campaign
    original = SesSender.singleton_class.instance_method(:send_bulk)
    SesSender.singleton_class.define_method(:send_bulk) do |**kwargs|
      unless campaign.deliveries.exists?(subscriber: a)
        campaign.deliveries.create!(subscriber: a, status: "sent", ses_message_id: "other-run", sent_at: Time.current)
      end
      original.bind_call(self, **kwargs)
    end
    begin
      with_stub_ses { SendCampaignJob.perform_now(@campaign.id) }
    ensure
      SesSender.singleton_class.define_method(:send_bulk, original)
    end

    assert_equal 1, @campaign.reload.stats["duplicates"]
    a.reload
    assert_equal 5, a.times_contacted, "already-delivered should not increment contact count"
    assert_equal contacted_at, a.last_contacted_at
    assert_equal 1, b.reload.times_contacted
  end
end
