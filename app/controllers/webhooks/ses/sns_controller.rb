# Public SNS webhook for SES bounce + complaint notifications.
#
# Each tenant points their SNS topic at this URL. The webhook routes the
# notification back to the correct team by looking up
# Team::SesConfiguration via the topic ARN — so tenants are isolated and
# one team's bounces never affect another's subscribers.
#
# Mounted outside the Account:: namespace so it's reachable without auth
# (SNS does its own signing; for MVP we accept TopicArn match as proof and
# rely on routing isolation. Signature verification is a follow-up.)
#
# In addition to flipping subscriber flags (used by segment filters), we now
# update the matching `Delivery` row by `ses_message_id` so per-campaign
# postmortems show real bounce/complaint/delivered counts. If no delivery
# row matches (event from before this rollout, or a different system), we
# still update the subscriber and log a miss.
class Webhooks::Ses::SnsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!, raise: false

  def create
    payload =
      begin
        JSON.parse(request.body.read)
      rescue JSON::ParserError
        head :bad_request and return
      end

    case payload["Type"]
    when "SubscriptionConfirmation"
      handle_subscription_confirmation(payload)
      head :ok
    when "Notification"
      handle_notification(payload)
      head :ok
    when "UnsubscribeConfirmation"
      # SNS sends one when a subscription is removed. Nothing to do.
      head :ok
    else
      head :bad_request
    end
  end

  private

  def handle_subscription_confirmation(payload)
    topic_arn = payload["TopicArn"]
    config = config_for_topic(topic_arn)
    return unless config

    # Confirming requires a GET to the SubscribeURL. Net::HTTP is fine here.
    subscribe_url = payload["SubscribeURL"]
    return unless subscribe_url.present?

    require "net/http"
    begin
      Net::HTTP.get(URI(subscribe_url))
      Rails.logger.info("[SNS] confirmed subscription for team=#{config.team_id} topic=#{topic_arn}")
    rescue => e
      Rails.logger.warn("[SNS] failed to confirm subscription for team=#{config.team_id} topic=#{topic_arn}: #{e.class}: #{e.message}")
    end
  end

  def handle_notification(payload)
    topic_arn = payload["TopicArn"]
    config = config_for_topic(topic_arn)
    return unless config

    message =
      begin
        JSON.parse(payload["Message"].to_s)
      rescue JSON::ParserError
        Rails.logger.warn("[SNS] malformed Message JSON on topic=#{topic_arn}")
        return
      end

    team = config.team

    # SES publishes two different notification shapes to SNS:
    #   1. "SES Notifications" (legacy, set via VerifiedEmail/Identity): uses `notificationType`.
    #   2. "SES Event Publishing" (configuration set → SNS destination, what we use): uses `eventType`.
    # We accept either key so the handler works for both wirings.
    event_type = message["eventType"] || message["notificationType"]
    mail = message["mail"] || {}
    message_id = mail["messageId"]
    Rails.logger.info("[SNS] received event_type=#{event_type.inspect} team=#{team.id} topic=#{topic_arn} message_id=#{message_id.inspect}")

    case event_type
    when "Bounce"
      handle_bounce(team, message["bounce"] || {}, message_id)
    when "Complaint"
      handle_complaint(team, message["complaint"] || {}, message_id)
    when "Reject"
      handle_reject(team, message["reject"] || {}, mail, message_id)
    when "Delivery"
      handle_delivery(team, message_id)
    when "Send"
      # Positive confirmation SES accepted the message for delivery. We
      # already wrote a `sent` Delivery row when calling SES; the row exists
      # before this event arrives. No-op aside from logging.
      Rails.logger.info("[SNS:send] team=#{team.id} message_id=#{message_id.inspect}")
    when "RenderingFailure", "Open", "Click"
      # RenderingFailure is a code bug to surface elsewhere. Open + Click
      # arrive only when SES-side tracking is enabled on the configuration
      # set; we use client-side tracking instead (Phase 2) so this is dead
      # code today — but we still log so we'd notice if it started firing.
      Rails.logger.info("[SNS:#{event_type.to_s.downcase}] team=#{team.id}")
    end
  end

  def config_for_topic(topic_arn)
    return nil if topic_arn.blank?
    scope = Team::SesConfiguration.where(sns_bounce_topic_arn: topic_arn)
      .or(Team::SesConfiguration.where(sns_complaint_topic_arn: topic_arn))
    # Delivery topic was added with the Ses::SnsAutoWire rollout. The
    # column may not exist on environments that haven't run the
    # 20260518170000 migration yet — guard the lookup so the webhook
    # still works on partial schemas.
    if Team::SesConfiguration.column_names.include?("sns_delivery_topic_arn")
      scope = scope.or(Team::SesConfiguration.where(sns_delivery_topic_arn: topic_arn))
    end
    scope.first
  end

  # Permanent bounces auto-unsubscribe the recipient. Soft bounces (transient)
  # are left alone — SES will retry; if it gives up it'll send a permanent
  # bounce later. The Delivery row is updated for *any* bounce, hard or
  # soft, so the postmortem reflects all observed bounce events.
  def handle_bounce(team, bounce, message_id)
    bounce_type = bounce["bounceType"]

    update_delivery_for(message_id) do |delivery|
      delivery.update!(
        status: "bounced",
        bounced_at: Time.current,
        bounce_subtype: bounce_type
      )
    end

    return unless bounce_type == "Permanent"

    bounce_subtype = bounce["bounceSubType"]

    Array(bounce["bouncedRecipients"]).each do |recipient|
      email = recipient["emailAddress"].to_s.downcase
      next if email.blank?

      # Auto-add to the suppression list FIRST so we never re-send to this
      # address even if the subscriber lookup fails (e.g. address is in the
      # audience via an inline import but the Subscriber row was already
      # purged). Idempotent — re-fires of the same SNS event are a no-op.
      Suppression.suppress(team: team, email: email, reason: "hard_bounce", source: bounce_subtype)

      subscriber = team.subscribers.find_by(email: email)
      next unless subscriber

      subscriber.update!(subscribed: false, bounced_at: Time.current)
      Rails.logger.info("[SNS:bounce] team=#{team.id} email=#{email} unsubscribed (permanent)")
    end
  end

  # Reject events fire when SES refuses to send (e.g. message contains a
  # virus, or content was flagged). The destination list lives on the
  # `mail` envelope. We treat the recipient as bounced — the message
  # never made it out and won't on a resend either.
  def handle_reject(team, reject, mail, message_id)
    reason = reject["reason"]

    update_delivery_for(message_id) do |delivery|
      delivery.update!(
        status: "failed",
        error_message: "rejected: #{reason}"
      )
    end

    Array(mail["destination"]).each do |raw_email|
      email = raw_email.to_s.downcase
      next if email.blank?
      subscriber = team.subscribers.find_by(email: email)
      next unless subscriber

      subscriber.update!(subscribed: false, bounced_at: Time.current)
      Rails.logger.info("[SNS:reject] team=#{team.id} email=#{email} unsubscribed (reason=#{reason})")
    end
  end

  # Any complaint auto-unsubscribes (and we record `complained_at`). The
  # underlying email provider will already have raised our complaint
  # rate — we just want to make sure we never send to this address again.
  def handle_complaint(team, complaint, message_id)
    update_delivery_for(message_id) do |delivery|
      delivery.update!(status: "complained", complained_at: Time.current)
    end

    feedback_type = complaint["complaintFeedbackType"]

    Array(complaint["complainedRecipients"]).each do |recipient|
      email = recipient["emailAddress"].to_s.downcase
      next if email.blank?

      # Complaints are a stronger signal than bounces — the recipient
      # actively flagged us. Add to the suppression list unconditionally so
      # no future campaign can re-add this address. Idempotent on re-fires.
      Suppression.suppress(team: team, email: email, reason: "complaint", source: feedback_type)

      subscriber = team.subscribers.find_by(email: email)
      next unless subscriber

      subscriber.update!(subscribed: false, complained_at: Time.current)
      Rails.logger.info("[SNS:complaint] team=#{team.id} email=#{email} unsubscribed (complaint)")
    end
  end

  # Delivery events confirm SES handed the message off to the receiving MTA.
  # No subscriber-side action; this exists purely to stamp the Delivery row
  # so the postmortem can show a delivered count.
  def handle_delivery(team, message_id)
    update_delivery_for(message_id) do |delivery|
      # If the row was already marked bounced/complained by an out-of-order
      # event, keep that terminal status — `delivered` shouldn't undo it.
      attrs = {delivered_at: Time.current}
      attrs[:status] = "delivered" if delivery.status == "sent"
      delivery.update!(attrs)
    end
    Rails.logger.info("[SNS:delivery] team=#{team.id} message_id=#{message_id.inspect}")
  end

  # Find the Delivery row by SES MessageId and yield it for in-place update.
  # If we have no message_id, or no row matches it (event from before this
  # rollout, or from a parallel system), log + skip — the subscriber-flag
  # updates still happen in the caller.
  def update_delivery_for(message_id)
    return if message_id.blank?
    delivery = Delivery.find_by(ses_message_id: message_id)
    if delivery.nil?
      Rails.logger.info("[SNS] no Delivery match for message_id=#{message_id.inspect}")
      return
    end
    yield delivery
  rescue => e
    # Don't let a delivery update error fail the webhook — SNS will retry
    # the whole notification and we'd then double-apply the subscriber flag.
    Rails.logger.warn("[SNS] failed to update Delivery message_id=#{message_id.inspect}: #{e.class}: #{e.message}")
  end
end
