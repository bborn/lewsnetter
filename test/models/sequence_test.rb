require "test_helper"

class SequenceTest < ActiveSupport::TestCase
  setup do
    @sequence = create(:sequence, :live)
    @team = @sequence.team
    create(:sequence_step, sequence: @sequence, delay_minutes: 30)
    @subscriber = create(:subscriber, team: @team)
  end

  test "enroll! schedules the first step after its delay" do
    freeze_time do
      enrollment = @sequence.enroll!(@subscriber)
      assert enrollment.persisted?
      assert_equal "active", enrollment.state
      assert_equal 0, enrollment.current_step
      assert_equal 30.minutes.from_now, enrollment.next_send_at
    end
  end

  test "enroll! does nothing when the team flag is off" do
    @team.update!(sequences_enabled: false)
    assert_nil @sequence.enroll!(@subscriber)
    assert_equal 0, @sequence.enrollments.count
  end

  test "enroll! does nothing for draft or paused sequences" do
    %w[draft paused].each do |status|
      @sequence.update!(status: status)
      assert_nil @sequence.enroll!(@subscriber), status
    end
  end

  test "enroll! turns away unsubscribed and suppressed subscribers" do
    @subscriber.update!(subscribed: false)
    assert_nil @sequence.enroll!(@subscriber)

    other = create(:subscriber, team: @team, email: "blocked@example.com")
    Suppression.suppress(team: @team, email: "blocked@example.com", reason: "hard_bounce")
    assert_nil @sequence.enroll!(other)
  end

  test "enroll! ignores a subscriber from another team" do
    assert_nil @sequence.enroll!(create(:subscriber))
  end

  test "enroll! never creates a second active enrollment" do
    assert @sequence.enroll!(@subscriber)
    assert_nil @sequence.enroll!(@subscriber)
    assert_equal 1, @sequence.enrollments.count
  end

  test "without reentry_days a subscriber goes through once ever" do
    @sequence.enroll!(@subscriber).update!(state: "completed")
    travel 400.days do
      assert_nil @sequence.enroll!(@subscriber)
    end
  end

  test "reentry_days lets a subscriber back in once the window has passed" do
    @sequence.update!(reentry_days: 7)
    @sequence.enroll!(@subscriber).update!(state: "completed")

    travel 6.days do
      assert_nil @sequence.enroll!(@subscriber)
    end
    travel 7.days + 1.minute do
      assert @sequence.enroll!(@subscriber)
    end
    assert_equal 2, @sequence.enrollments.where(subscriber: @subscriber).count
  end

  test "enroll! skips subscribers already in the exit segment" do
    @sequence.update!(exit_segment: paid_segment)
    @subscriber.update!(custom_attributes: {"plan" => "paid"})
    assert_nil @sequence.enroll!(@subscriber)
  end

  test "activating requires a sender address" do
    sequence = build(:sequence, team: @team, status: "active", sender_address: nil)
    assert_not sequence.valid?
    assert_includes sequence.errors[:sender_address].join, "required"
  end

  test "segment trigger requires a trigger segment from the same team" do
    sequence = build(:sequence, team: @team, trigger_type: "segment", trigger_segment: nil)
    assert_not sequence.valid?

    sequence.trigger_segment = create(:segment) # other team
    assert_not sequence.valid?

    sequence.trigger_segment = create(:segment, team: @team)
    assert sequence.valid?, sequence.errors.full_messages.to_sentence
  end

  test "each step owns a hidden backing campaign kept in sync" do
    step = @sequence.steps.first
    campaign = step.campaign
    assert_equal "sequence", campaign.status
    assert_equal step.subject, campaign.subject
    assert_equal @sequence.sender_address, campaign.sender_address
    assert_not campaign.sendable?
    assert_not_includes @team.campaigns.visible, campaign

    step.update!(subject: "New subject", body_markdown: "New body")
    assert_equal "New subject", campaign.reload.subject
    assert_equal "New body", campaign.body_markdown

    new_sender = create(:sender_address, team: @team, verified: true, ses_status: "verified")
    @sequence.update!(sender_address: new_sender)
    assert_equal new_sender, campaign.reload.sender_address
  end

  test "step_stats reports waiting, sent and skipped per step" do
    second = create(:sequence_step, sequence: @sequence, delay_minutes: 60)
    @sequence.enroll!(@subscriber)
    other = create(:subscriber, team: @team)
    @sequence.enroll!(other).update!(current_step: 1)
    Delivery.create!(campaign: second.campaign, subscriber: other, ses_message_id: "m-1", sent_at: Time.current)
    second.update_column(:skipped_count, 2)

    stats = @sequence.reload.step_stats
    assert_equal [1, 2], stats.map { it[:position] }
    assert_equal [1, 1], stats.map { it[:waiting] }
    assert_equal [0, 1], stats.map { it[:sent] }
    assert_equal [0, 2], stats.map { it[:skipped] }
  end

  test "destroying a sequence removes its steps, backing campaigns and enrollments" do
    @sequence.enroll!(@subscriber)
    campaign_id = @sequence.steps.first.campaign_id
    @sequence.destroy!
    assert_not Campaign.exists?(campaign_id)
    assert_equal 0, SequenceEnrollment.where(sequence_id: @sequence.id).count
  end

  test "destroying the team cleans up sequences" do
    @sequence.enroll!(@subscriber)
    @team.destroy!
    assert_not Sequence.exists?(@sequence.id)
  end

  private

  def paid_segment
    create(:segment, team: @team,
      definition: {"predicate" => "json_extract(custom_attributes, '$.plan') = 'paid'"})
  end
end
