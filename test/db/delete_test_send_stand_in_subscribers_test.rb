require "test_helper"
require Rails.root.join("db/migrate/20261118130100_delete_test_send_stand_in_subscribers")

class DeleteTestSendStandInSubscribersTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @campaign = @team.campaigns.create!(subject: "Hi", body_markdown: "Hello", status: "sent")
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { DeleteTestSendStandInSubscribers.new.up }
  end

  test "deletes stand-in subscribers with their deliveries, events and enrollments, and nothing else" do
    stand_ins = %w[test-1 mcp-test-1 preview-as-783].map do |external_id|
      @team.subscribers.create!(email: "author@example.com", external_id: external_id, subscribed: true)
    end
    keep = @team.subscribers.create!(email: "real@example.com", external_id: "test-abc", subscribed: true)

    delivery = @campaign.deliveries.create!(subscriber: stand_ins.first, status: "sent", ses_message_id: "t1")
    OpenEvent.create!(delivery: delivery, opened_at: Time.current)
    ClickEvent.create!(delivery: delivery, url: "https://example.com", clicked_at: Time.current)
    Event.create!(team: @team, subscriber: stand_ins.second, name: "signed_up", occurred_at: Time.current)
    sequence = create(:sequence, :live, team: @team)
    sequence.enrollments.create!(subscriber: stand_ins.third, state: "active", current_step: 0, enrolled_at: Time.current, next_send_at: 1.day.from_now)
    kept_delivery = @campaign.deliveries.create!(subscriber: keep, status: "sent", ses_message_id: "k1")

    run_migration

    assert_equal [keep.id], @team.subscribers.pluck(:id)
    assert_equal [kept_delivery.id], Delivery.pluck(:id)
    assert_equal 0, OpenEvent.count + ClickEvent.count
    assert_equal 0, Event.where(subscriber_id: stand_ins.map(&:id)).count
    assert_equal 0, SequenceEnrollment.where(subscriber_id: stand_ins.map(&:id)).count
  end

  test "running it again changes nothing" do
    @team.subscribers.create!(email: "author@example.com", external_id: "test-1", subscribed: true)
    run_migration

    assert_no_difference -> { Subscriber.count } do
      run_migration
    end
  end
end
