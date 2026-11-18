require "test_helper"

class ScheduledCampaignDispatchJobTest < ActiveJob::TestCase
  # The test env runs jobs inline; use the test adapter so enqueues are
  # visible and run only when we say so.
  def queue_adapter_for_test
    ActiveJob::QueueAdapters::TestAdapter.new
  end

  setup do
    @team = create(:team)
    @other_team = create(:team)
    @team.subscribers.create!(email: "a@example.com", external_id: "sched-a", subscribed: true)
  end

  def campaign(team, status:, scheduled_for: nil)
    team.campaigns.create!(subject: "Hi", body_markdown: "Hello", status: status, scheduled_for: scheduled_for)
  end

  test "enqueues a send for every due scheduled campaign across teams" do
    due = campaign(@team, status: "scheduled", scheduled_for: 5.minutes.ago)
    due_elsewhere = campaign(@other_team, status: "scheduled", scheduled_for: 1.minute.ago)
    campaign(@team, status: "scheduled", scheduled_for: 1.hour.from_now)
    campaign(@team, status: "draft", scheduled_for: 1.hour.ago)
    campaign(@team, status: "scheduled", scheduled_for: nil)

    ScheduledCampaignDispatchJob.perform_now

    enqueued = enqueued_jobs.select { |j| j[:job] == SendCampaignJob }.map { |j| j[:args].first }
    assert_equal [due.id, due_elsewhere.id].sort, enqueued.sort
  end

  # The app was down when scheduled_for passed: it still goes out.
  test "a campaign whose time passed long ago is still sent" do
    overdue = campaign(@team, status: "scheduled", scheduled_for: 3.days.ago)

    ScheduledCampaignDispatchJob.perform_now

    assert_enqueued_with(job: SendCampaignJob, args: [overdue.id])
  end

  test "overlapping ticks send a scheduled campaign exactly once" do
    due = campaign(@team, status: "scheduled", scheduled_for: 1.minute.ago)
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub

    ScheduledCampaignDispatchJob.perform_now
    ScheduledCampaignDispatchJob.perform_now
    assert_equal 2, enqueued_jobs.count { |j| j[:job] == SendCampaignJob }

    perform_enqueued_jobs

    assert_equal "sent", due.reload.status
    assert_equal 1, due.deliveries.count
  ensure
    Rails.application.config.ses_client = original
  end

  test "is registered as a recurring task in development and production" do
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
    %w[development production].each do |env|
      task = config.fetch(env).fetch("scheduled_campaign_dispatch")
      assert_equal "ScheduledCampaignDispatchJob", task["class"], env
      assert_equal "every minute", task["schedule"], env
      assert config.fetch(env).key?("sequence_dispatch"), "#{env} kept sequence_dispatch"
    end
  end
end
