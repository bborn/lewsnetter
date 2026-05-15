# frozen_string_literal: true

module Mcp
  module Tools
    # Serialization helpers shared across all MCP tools. Include this module
    # in a tool class or call methods directly via the module.
    #
    # Conventions (followed by every method here):
    #   - Symbol keys in the returned hash.
    #   - Datetime fields are ISO8601 strings or nil (never raw Time objects).
    #   - JSON columns (custom_attributes, properties) are returned as plain
    #     hashes with string keys, exactly as stored. nil columns coerce to {}.
    module Serializers
      module_function

      def serialize_subscriber(sub)
        {
          id: sub.id,
          email: sub.email,
          name: sub.name,
          external_id: sub.external_id,
          subscribed: sub.subscribed,
          unsubscribed_at: sub.unsubscribed_at&.iso8601,
          bounced_at: sub.bounced_at&.iso8601,
          complained_at: sub.complained_at&.iso8601,
          company_id: sub.company_id,
          custom_attributes: sub.custom_attributes || {},
          created_at: sub.created_at.iso8601,
          updated_at: sub.updated_at.iso8601
        }
      end

      def serialize_segment(seg)
        pred = seg.predicate
        count = if pred.present?
          begin
            seg.applies_to(seg.team.subscribers).count
          rescue Segment::InvalidPredicate
            nil
          end
        end
        {
          id: seg.id,
          name: seg.name,
          natural_language_source: seg.natural_language_source,
          predicate: pred,
          estimated_count: count,
          created_at: seg.created_at.iso8601,
          updated_at: seg.updated_at.iso8601
        }
      end

      # EmailTemplate schema: id, team_id, name, mjml_body, rendered_html,
      # created_at, updated_at. Assets are Active Storage attachments.
      def serialize_email_template(t)
        {
          id: t.id,
          name: t.name,
          mjml_body: t.mjml_body,
          created_at: t.created_at.iso8601,
          updated_at: t.updated_at.iso8601
        }
      end

      def serialize_campaign(c)
        {
          id: c.id,
          subject: c.subject,
          preheader: c.preheader,
          status: c.status,
          body_markdown: c.body_markdown,
          body_mjml: c.body_mjml,
          email_template_id: c.email_template_id,
          segment_id: c.segment_id,
          sender_address_id: c.sender_address_id,
          scheduled_for: c.scheduled_for&.iso8601,
          sent_at: c.sent_at&.iso8601,
          created_at: c.created_at.iso8601,
          updated_at: c.updated_at.iso8601
        }
      end

      # SenderAddress schema: id, team_id, email, name, verified (boolean),
      # ses_status (string), created_at, updated_at. No verified_at column.
      def serialize_sender_address(s)
        {
          id: s.id,
          email: s.email,
          name: s.name,
          verified: s.verified,
          ses_status: s.ses_status,
          created_at: s.created_at.iso8601,
          updated_at: s.updated_at.iso8601
        }
      end

      def serialize_event(e)
        {
          id: e.id,
          name: e.name,
          subscriber_id: e.subscriber_id,
          properties: e.properties || {},
          occurred_at: e.occurred_at&.iso8601,
          created_at: e.created_at.iso8601
        }
      end

      def serialize_company(c)
        {
          id: c.id,
          name: c.name,
          external_id: c.external_id,
          intercom_id: c.intercom_id,
          custom_attributes: c.custom_attributes || {},
          created_at: c.created_at.iso8601,
          updated_at: c.updated_at.iso8601
        }
      end
    end
  end
end
