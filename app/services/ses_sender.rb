# SesSender wraps AWS SES v2's SendEmail API. The job owns batching and stats;
# SesSender owns the per-recipient render + SES call.
#
# Per-tenant SES: the client comes from `Ses::ClientFor.call(campaign.team)`
# which reads that team's `Team::SesConfiguration`. Each tenant brings their
# own AWS credentials, so reputation is per-tenant and we don't need a global
# AWS account configured for MVP.
#
# Stub mode: when a team has no SES configured (dev/test or a brand-new
# tenant) we log a preview and return synthetic message ids so the rest of
# the pipeline (job, stats, status transitions) runs end-to-end. The
# `Rails.application.config.ses_client = :stub` override is also honored for
# tests that want to force stub behavior even when a config exists.
#
# Delivery records: every per-recipient attempt — success, failure, or stub —
# writes a `Delivery` row. The row's `ses_message_id` is the join key SNS
# event-publishing webhooks use to update the row with bounce/complaint/
# delivered events. Failed sends still get a row (status="failed") so the
# postmortem aggregations match the audience size.
class SesSender
  Result = Struct.new(:message_ids, :failed, :delivery_write_errors, keyword_init: true)

  class << self
    # campaign: Campaign with a sender_address + body
    # subscribers: enumerable of Subscriber records
    def send_bulk(campaign:, subscribers:)
      subscribers = Array(subscribers)
      return Result.new(message_ids: [], failed: [], delivery_write_errors: 0) if subscribers.empty?

      team = campaign.team
      client, stub_mode = resolve_client(team)
      from_address = build_from_address(campaign)
      configuration_set_name = resolve_configuration_set_name(team)

      message_ids = []
      failed = []
      delivery_write_errors = 0

      subscribers.each do |subscriber|
        # Phase 2: create the Delivery row BEFORE rendering so the renderer
        # can embed the row's tracking_token in the open pixel + click URLs.
        # The row starts with status="sent", ses_message_id=nil, sent_at=nil;
        # we backfill ses_message_id + sent_at after SES returns successfully,
        # or flip to status="failed" if anything in this loop iteration blows
        # up. If we can't even create the row (validation drift, DB hiccup),
        # we still attempt the render+send so the recipient gets the email —
        # we just don't get tracking on that one delivery.
        delivery = build_delivery(campaign: campaign, subscriber: subscriber)
        delivery_write_errors += 1 if delivery.nil?

        rendered =
          begin
            CampaignRenderer.new(campaign: campaign, subscriber: subscriber, delivery: delivery).call
          rescue => e
            Rails.logger.warn(
              "[SesSender] render failed for subscriber=#{subscriber.id} " \
              "campaign=#{campaign.id}: #{e.class}: #{e.message}"
            )
            failed << {subscriber: subscriber, error: "render_failed: #{e.message}"}
            mark_delivery_failed(delivery, "render_failed: #{e.message}")
            next
          end

        if stub_mode
          Rails.logger.info(
            %([SES STUB] to=#{subscriber.email} subject=#{rendered.subject.inspect} ) +
              %(html_preview=#{rendered.html.to_s[0, 200].inspect})
          )
          stub_id = "stub-#{SecureRandom.hex(8)}"
          message_ids << stub_id
          finalize_sent_delivery(delivery, ses_message_id: stub_id)
          next
        end

        begin
          send_args = {
            from_email_address: from_address,
            destination: {to_addresses: [subscriber.email]},
            content: {
              simple: {
                subject: {data: rendered.subject},
                body: {
                  html: {data: rendered.html},
                  text: {data: rendered.text}
                }
              }
            }
          }
          # Attaching the configuration set is what makes SES publish bounce/
          # complaint events to SNS. Without this argument, SES still sends,
          # but our webhook never sees the bounce.
          send_args[:configuration_set_name] = configuration_set_name if configuration_set_name.present?
          response = client.send_email(**send_args)
          message_ids << response.message_id
          finalize_sent_delivery(delivery, ses_message_id: response.message_id)
        rescue => e
          Rails.logger.warn(
            "[SesSender] SES send failed for subscriber=#{subscriber.id} " \
            "campaign=#{campaign.id}: #{e.class}: #{e.message}"
          )
          failed << {subscriber: subscriber, error: e.message}
          mark_delivery_failed(delivery, e.message)
        end
      end

      Result.new(message_ids: message_ids, failed: failed, delivery_write_errors: delivery_write_errors)
    end

    private

    # Phase 2: split row creation from row finalization so the renderer can
    # see the persisted Delivery (and use its id in the tracking token) BEFORE
    # we hand off to SES. The row starts in a "claimed but not sent" state —
    # status="sent" by default but with ses_message_id+sent_at still nil —
    # and is then promoted to a real sent/failed row by the helpers below.
    #
    # Wrapped in rescue so a single bad insert (FK gone, validation drift)
    # can't crash the entire batch send. Returns the saved record on success,
    # nil on failure (so the caller can bump a counter + skip tracking).
    def build_delivery(campaign:, subscriber:)
      Delivery.create!(
        campaign: campaign,
        subscriber: subscriber,
        status: "sent",
        ses_message_id: nil,
        sent_at: nil
      )
    rescue => e
      Rails.logger.warn(
        "[SesSender] failed to create Delivery for subscriber=#{subscriber.id} " \
        "campaign=#{campaign.id}: #{e.class}: #{e.message}"
      )
      nil
    end

    # Stamp the row as sent + tag with the SES (or stub) message id. Uses
    # update_columns to skip validations/callbacks — we already validated on
    # create and don't want to re-fire any per-save side effects.
    def finalize_sent_delivery(delivery, ses_message_id:)
      return if delivery.nil?
      delivery.update_columns(
        ses_message_id: ses_message_id,
        sent_at: Time.current,
        status: "sent",
        updated_at: Time.current
      )
    rescue => e
      Rails.logger.warn(
        "[SesSender] failed to finalize sent Delivery id=#{delivery.id}: #{e.class}: #{e.message}"
      )
    end

    def mark_delivery_failed(delivery, error_message)
      return if delivery.nil?
      delivery.update_columns(
        status: "failed",
        error_message: error_message,
        updated_at: Time.current
      )
    rescue => e
      Rails.logger.warn(
        "[SesSender] failed to mark Delivery id=#{delivery.id} failed: #{e.class}: #{e.message}"
      )
    end

    # Returns [client_or_nil, stub_mode_bool]. We're in stub mode when either:
    #   1. The global override `Rails.application.config.ses_client = :stub`
    #      is set — preserved so existing tests can force stub mode.
    #   2. The team has no SES configuration (NotConfigured) — every brand-new
    #      team starts here until they paste credentials.
    def resolve_client(team)
      global = Rails.application.config.respond_to?(:ses_client) ? Rails.application.config.ses_client : nil
      return [nil, true] if global == :stub

      begin
        [Ses::ClientFor.call(team), false]
      rescue Ses::ClientFor::NotConfigured
        Rails.logger.info(
          "[SesSender] team #{team.id} has no SES config — running in stub mode."
        )
        [nil, true]
      end
    end

    # Per-team override falls back to the shared default. We treat blank as
    # "use the default" so an empty string in the DB doesn't disable event
    # publishing.
    def resolve_configuration_set_name(team)
      configured = team.ses_configuration&.configuration_set_name.presence
      configured || "lewsnetter-default"
    end

    def build_from_address(campaign)
      if campaign.sender_address&.name.present?
        %("#{campaign.sender_address.name}" <#{campaign.sender_address.email}>)
      else
        campaign.sender_address&.email
      end
    end
  end
end
