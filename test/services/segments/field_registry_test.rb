require "test_helper"

module Segments
  class FieldRegistryTest < ActiveSupport::TestCase
    setup do
      @team = Team.create!(name: "Registry team")
      @team.subscribers.create!(email: "a@example.com", external_id: "a1",
        custom_attributes: {"last_active_at" => 3.days.ago.to_i, "reports_count" => 4}, tags: ["Connected Accts"])
    end

    def field(key)
      FieldRegistry.new(team: @team).call.values.flatten.find { |f| f[:key] == key }
    end

    test "integer *_at attributes holding epoch seconds are unix_time" do
      assert_equal :unix_time, field("custom_attributes.last_active_at")[:type]
      assert_equal :number, field("custom_attributes.reports_count")[:type]
      assert_includes FieldRegistry.operators_for(:unix_time), "more_than_days_ago"
    end

    test "tags are an array field sampled from subscribers" do
      tags = field("subscribers.tags")
      assert_equal :array, tags[:type]
      assert_equal ["Connected Accts"], tags[:samples]
    end
  end
end
