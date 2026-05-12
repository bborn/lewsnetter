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
    case message["notificationType"]
    when "Bounce"
      handle_bounce(team, message["bounce"] || {})
    when "Complaint"
      handle_complaint(team, message["complaint"] || {})
    when "Delivery"
      # We don't track per-recipient delivery yet — log and move on.
      Rails.logger.info("[SNS:delivery] team=#{team.id}")
    end
  end

  def config_for_topic(topic_arn)
    return nil if topic_arn.blank?
    Team::SesConfiguration.where(sns_bounce_topic_arn: topic_arn)
      .or(Team::SesConfiguration.where(sns_complaint_topic_arn: topic_arn))
      .first
  end

  # Permanent bounces auto-unsubscribe the recipient. Soft bounces (transient)
  # are left alone — SES will retry; if it gives up it'll send a permanent
  # bounce later.
  def handle_bounce(team, bounce)
    return unless bounce["bounceType"] == "Permanent"

    Array(bounce["bouncedRecipients"]).each do |recipient|
      email = recipient["emailAddress"].to_s.downcase
      next if email.blank?
      subscriber = team.subscribers.find_by(email: email)
      next unless subscriber

      subscriber.update!(subscribed: false, bounced_at: Time.current)
      Rails.logger.info("[SNS:bounce] team=#{team.id} email=#{email} unsubscribed (permanent)")
    end
  end

  # Any complaint auto-unsubscribes (and we record `complained_at`). The
  # underlying email provider will already have raised our complaint
  # rate — we just want to make sure we never send to this address again.
  def handle_complaint(team, complaint)
    Array(complaint["complainedRecipients"]).each do |recipient|
      email = recipient["emailAddress"].to_s.downcase
      next if email.blank?
      subscriber = team.subscribers.find_by(email: email)
      next unless subscriber

      subscriber.update!(subscribed: false, complained_at: Time.current)
      Rails.logger.info("[SNS:complaint] team=#{team.id} email=#{email} unsubscribed (complaint)")
    end
  end
end
