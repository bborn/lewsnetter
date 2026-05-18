# frozen_string_literal: true

module Account
  # Unified, time-ordered audit trail for a single subscriber. Answers the
  # power-user question "what did this person receive, did they engage, why
  # are they unsubscribed?" by fanning out across Delivery timestamp columns
  # and custom Event rows, then sorting newest first.
  #
  # Each Delivery can contribute up to 7 entries (sent / delivered / opened /
  # clicked / bounced / complained / unsubscribed) because the Delivery model
  # treats those timestamps as the source of truth — a row can legitimately
  # have both `delivered_at` and `bounced_at` set, and we want both events to
  # appear on the timeline rather than collapsing to a single "latest state".
  #
  # The caller (the show page) is the only consumer today; if more surfaces
  # need this list we can promote the entry shape to a Struct.
  class SubscriberTimeline
    DEFAULT_LIMIT = 100

    # Display kinds — also the values returned in the `:kind` field of each
    # entry. The view uses these to style dot colors / labels.
    KINDS = %w[
      signup
      campaign_sent
      delivered
      opened
      clicked
      bounced
      complained
      unsubscribed
      custom_event
    ].freeze

    def initialize(subscriber:, limit: DEFAULT_LIMIT)
      @subscriber = subscriber
      @limit = limit
    end

    # Returns an Array of Hashes ordered by `:at` desc. See the class doc for
    # the entry shape. We over-fetch from each source then take the top
    # `limit` after the merge — sorting in Ruby is cheap at this size and
    # avoids a UNION across heterogeneous columns.
    def call
      entries = []
      entries.concat(signup_entries)
      entries.concat(delivery_entries)
      entries.concat(event_entries)

      entries
        .sort_by { |e| -e[:at].to_f }
        .first(@limit)
    end

    private

    attr_reader :subscriber, :limit

    def signup_entries
      return [] unless subscriber.created_at

      [{
        at: subscriber.created_at,
        kind: "signup",
        title: "Subscriber added",
        subtitle: subscriber.email.presence,
        url: nil,
        delivery_id: nil
      }]
    end

    # One Delivery -> up to 7 entries. Preload the campaign so the view + the
    # subtitle here avoid an N+1 per row.
    def delivery_entries
      deliveries = subscriber.deliveries.includes(:campaign)
      deliveries.flat_map { |d| entries_for_delivery(d) }
    end

    def entries_for_delivery(delivery)
      campaign = delivery.campaign
      subject = campaign&.subject.presence || "Untitled campaign"
      campaign_url = campaign ? Rails.application.routes.url_helpers.account_campaign_path(campaign) : nil
      delivery_id = delivery.id

      rows = []

      if delivery.sent_at
        rows << {
          at: delivery.sent_at,
          kind: "campaign_sent",
          title: "Sent: #{subject}",
          subtitle: campaign ? "Campaign ##{campaign.id}" : nil,
          url: campaign_url,
          delivery_id: delivery_id
        }
      end

      if delivery.delivered_at
        rows << {
          at: delivery.delivered_at,
          kind: "delivered",
          title: "Delivered: #{subject}",
          subtitle: nil,
          url: campaign_url,
          delivery_id: delivery_id
        }
      end

      if delivery.opened_at
        rows << {
          at: delivery.opened_at,
          kind: "opened",
          title: "Opened: #{subject}",
          subtitle: nil,
          url: campaign_url,
          delivery_id: delivery_id
        }
      end

      if delivery.clicked_at
        rows << {
          at: delivery.clicked_at,
          kind: "clicked",
          title: "Clicked: #{subject}",
          subtitle: delivery.last_clicked_url.presence,
          url: delivery.last_clicked_url.presence || campaign_url,
          delivery_id: delivery_id
        }
      end

      if delivery.bounced_at
        bounce_label = delivery.bounce_subtype.present? ? "Bounced (#{delivery.bounce_subtype}): #{subject}" : "Bounced: #{subject}"
        rows << {
          at: delivery.bounced_at,
          kind: "bounced",
          title: bounce_label,
          subtitle: delivery.error_message.presence,
          url: campaign_url,
          delivery_id: delivery_id
        }
      end

      if delivery.complained_at
        rows << {
          at: delivery.complained_at,
          kind: "complained",
          title: "Complained: #{subject}",
          subtitle: nil,
          url: campaign_url,
          delivery_id: delivery_id
        }
      end

      if delivery.unsubscribed_at
        rows << {
          at: delivery.unsubscribed_at,
          kind: "unsubscribed",
          title: "Unsubscribed via: #{subject}",
          subtitle: nil,
          url: campaign_url,
          delivery_id: delivery_id
        }
      end

      rows
    end

    def event_entries
      subscriber.events.order(occurred_at: :desc).limit(limit).map do |event|
        properties_peek = event.properties.present? ? event.properties.to_json.truncate(120) : nil

        {
          at: event.occurred_at,
          kind: "custom_event",
          title: event.name.to_s,
          subtitle: properties_peek,
          url: safe_event_url(event),
          delivery_id: nil
        }
      end
    end

    # Guard against routing errors in environments where the polymorphic
    # account_event_path isn't reachable (e.g. tests without host config).
    def safe_event_url(event)
      Rails.application.routes.url_helpers.account_event_path(event)
    rescue StandardError
      nil
    end
  end
end
