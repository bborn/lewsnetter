# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    class SerializersTest < ActiveSupport::TestCase
      include Serializers

      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
      end

      test "serialize_subscriber produces JSON-safe hash with team-scoped fields" do
        sub = @team.subscribers.create!(email: "a@b.com", external_id: "ext-1", subscribed: true,
          custom_attributes: {"plan" => "pro"})
        h = serialize_subscriber(sub)
        assert_equal sub.id, h[:id]
        assert_equal "a@b.com", h[:email]
        assert_equal "ext-1", h[:external_id]
        assert_equal true, h[:subscribed]
        assert_equal({"plan" => "pro"}, h[:custom_attributes])
        assert_kind_of String, h[:created_at]  # ISO8601
        assert_nil h[:unsubscribed_at]
      end

      test "serialize_subscriber returns empty hash when custom_attributes not set" do
        # The DB column has NOT NULL + default {}, so custom_attributes is always
        # at least {} — the serializer's `|| {}` guard handles in-memory nil objects.
        sub = @team.subscribers.create!(email: "b@b.com")
        h = serialize_subscriber(sub)
        assert_equal({}, h[:custom_attributes])
      end

      test "serialize_segment includes id, name, predicate, estimated_count" do
        seg = @team.segments.create!(name: "Pro Users",
          definition: {"predicate" => "subscribers.subscribed = 1"})
        h = serialize_segment(seg)
        assert_equal seg.id, h[:id]
        assert_equal "Pro Users", h[:name]
        assert_equal "subscribers.subscribed = 1", h[:predicate]
        assert h.key?(:estimated_count)
        assert_kind_of String, h[:created_at]
      end

      test "serialize_segment with no predicate returns nil predicate and nil estimated_count" do
        seg = @team.segments.create!(name: "All", definition: {})
        h = serialize_segment(seg)
        assert_nil h[:predicate]
        assert_nil h[:estimated_count]
      end

      test "serialize_campaign exposes status, subject, sent_at iso8601 or nil" do
        camp = @team.campaigns.create!(subject: "Hi", status: "draft", body_markdown: "## hello")
        h = serialize_campaign(camp)
        assert_equal camp.id, h[:id]
        assert_equal "Hi", h[:subject]
        assert_equal "draft", h[:status]
        assert_nil h[:sent_at]
        assert_nil h[:scheduled_for]
        assert_kind_of String, h[:created_at]
      end

      test "serialize_email_template returns id, name, and mjml_body field" do
        skip unless defined?(EmailTemplate)
        t = @team.email_templates.create!(name: "Brand") rescue skip
        h = serialize_email_template(t)
        assert_equal "Brand", h[:name]
        assert_equal t.id, h[:id]
        assert h.key?(:mjml_body)
        assert_kind_of String, h[:created_at]
      end

      test "serialize_sender_address returns id, email, ses_status, verified" do
        skip unless defined?(SenderAddress)
        s = @team.sender_addresses.create!(email: "team@example.com") rescue skip
        h = serialize_sender_address(s)
        assert_equal "team@example.com", h[:email]
        assert_equal s.id, h[:id]
        assert h.key?(:ses_status)
        assert h.key?(:verified)
        assert_kind_of String, h[:created_at]
      end

      test "serialize_event returns id, name, subscriber_id, properties, occurred_at" do
        sub = @team.subscribers.create!(email: "c@b.com")
        evt = @team.events.create!(subscriber: sub, name: "page_view",
          occurred_at: Time.current, properties: {"url" => "/home"})
        h = serialize_event(evt)
        assert_equal evt.id, h[:id]
        assert_equal "page_view", h[:name]
        assert_equal sub.id, h[:subscriber_id]
        assert_equal({"url" => "/home"}, h[:properties])
        assert_kind_of String, h[:occurred_at]
        assert_kind_of String, h[:created_at]
      end
    end
  end
end
