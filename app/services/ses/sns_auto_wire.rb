# frozen_string_literal: true

# Idempotent automation of the SES → SNS → Lewsnetter webhook wiring.
#
# Replaces the manual "create three SNS topics, subscribe each one, create
# a configuration set, add event destinations, copy ARNs back into
# Lewsnetter" toil. Uses the team's existing SES IAM credentials (paste
# step 1 of the wizard) to do everything on the user's behalf.
#
# Each step is independently rescued — partial success still returns the
# topic ARNs that *did* get created and persisted, so a re-run can close
# the gaps rather than starting over.
#
# Region: SNS topics + the SES configuration set MUST live in the same
# region as the team's SES credentials. Both clients are built from
# `team.ses_configuration.region`.
module Ses
  class SnsAutoWire
    CONFIGURATION_SET_NAME = "lewsnetter-default"
    EVENT_DESTINATION_NAME = "lewsnetter-events"

    # Topic kind → (topic name suffix, SES event type the destination
    # should subscribe to, attribute on Team::SesConfiguration to persist
    # the topic ARN into).
    TOPICS = {
      bounce: {
        name: "lewsnetter-ses-bounces",
        event_type: "BOUNCE",
        attribute: :sns_bounce_topic_arn
      },
      complaint: {
        name: "lewsnetter-ses-complaints",
        event_type: "COMPLAINT",
        attribute: :sns_complaint_topic_arn
      },
      delivery: {
        name: "lewsnetter-ses-deliveries",
        event_type: "DELIVERY",
        attribute: :sns_delivery_topic_arn
      }
    }.freeze

    Result = Struct.new(:ok, :summary, :error_message, keyword_init: true) do
      def ok? = !!ok
    end

    def initialize(team:, webhook_url:)
      @team = team
      @webhook_url = webhook_url
      @summary = {
        configuration_set: {action: nil, name: CONFIGURATION_SET_NAME, error: nil},
        topics: {},
        subscriptions: {},
        event_destination: {action: nil, name: EVENT_DESTINATION_NAME, error: nil},
        region: nil,
        webhook_url: webhook_url
      }
      @errors = []
    end

    def call
      config = @team.ses_configuration
      return failure("Team has no SES configured") unless config&.configured?
      @summary[:region] = config.region

      @ses = Ses::ClientFor.call(@team)
      @sns = Ses::ClientFor.sns_client_for(@team)

      ensure_configuration_set
      ensure_topics
      ensure_subscriptions
      persist_topic_arns
      ensure_event_destination

      Result.new(
        ok: @errors.empty?,
        summary: @summary,
        error_message: @errors.empty? ? nil : @errors.join("; ")
      )
    rescue Ses::ClientFor::NotConfigured => e
      failure(e.message)
    rescue Aws::Errors::MissingCredentialsError => e
      failure("AWS credentials missing: #{e.message}")
    rescue => e
      Rails.logger.warn("[Ses::SnsAutoWire] unexpected #{e.class}: #{e.message}")
      failure("Unexpected: #{e.class}: #{e.message}")
    end

    private

    def failure(message)
      Result.new(ok: false, summary: @summary, error_message: message)
    end

    # SESv2 CreateConfigurationSet is idempotent only in the sense that a
    # second call with the same name raises AlreadyExists — which we treat
    # as success. We also call DescribeConfigurationSet (SES v1) is *not*
    # part of SESv2; SESv2's GetConfigurationSet returns the set details
    # if present, NotFound if not. Use that for the "exists?" probe.
    def ensure_configuration_set
      @ses.get_configuration_set(configuration_set_name: CONFIGURATION_SET_NAME)
      @summary[:configuration_set][:action] = :exists
    rescue Aws::SESV2::Errors::NotFoundException
      @ses.create_configuration_set(configuration_set_name: CONFIGURATION_SET_NAME)
      @summary[:configuration_set][:action] = :created
    rescue Aws::SESV2::Errors::ServiceError => e
      @errors << "configuration_set: #{e.message}"
      @summary[:configuration_set][:error] = e.message
    end

    # SNS CreateTopic is genuinely idempotent — re-creating with the same
    # name returns the existing ARN. We rely on that rather than a separate
    # "does it exist?" probe (ListTopics would require pagination across
    # hundreds of unrelated topics for a busy AWS account).
    def ensure_topics
      TOPICS.each do |kind, meta|
        existing_arn = @team.ses_configuration.public_send(meta[:attribute]).to_s
        response = @sns.create_topic(name: meta[:name])
        arn = response.topic_arn
        @summary[:topics][kind] = {
          arn: arn,
          name: meta[:name],
          action: (existing_arn == arn) ? :exists : (existing_arn.present? ? :replaced : :created),
          error: nil
        }
      rescue Aws::SNS::Errors::ServiceError => e
        @errors << "topic[#{kind}]: #{e.message}"
        @summary[:topics][kind] = {arn: nil, name: meta[:name], action: nil, error: e.message}
      end
    end

    # Subscription idempotency: SNS Subscribe with a duplicate (TopicArn,
    # Protocol, Endpoint) triple returns the existing SubscriptionArn
    # (which is "PendingConfirmation" until SNS POSTs the confirmation to
    # the webhook and our SNS controller fetches the SubscribeURL). We do
    # an explicit ListSubscriptionsByTopic first so the summary can
    # distinguish "already wired" from "newly created" — and so we don't
    # spam Subscribe calls (which trigger fresh confirmation POSTs).
    def ensure_subscriptions
      TOPICS.each do |kind, _meta|
        topic_arn = @summary.dig(:topics, kind, :arn)
        next if topic_arn.blank?

        existing = find_existing_subscription(topic_arn, @webhook_url)
        if existing
          @summary[:subscriptions][kind] = {
            arn: existing,
            action: :exists,
            error: nil
          }
          next
        end

        response = @sns.subscribe(
          topic_arn: topic_arn,
          protocol: "https",
          endpoint: @webhook_url,
          return_subscription_arn: true
        )
        @summary[:subscriptions][kind] = {
          arn: response.subscription_arn,
          action: :created,
          error: nil
        }
      rescue Aws::SNS::Errors::ServiceError => e
        @errors << "subscription[#{kind}]: #{e.message}"
        @summary[:subscriptions][kind] = {arn: nil, action: nil, error: e.message}
      end
    end

    def find_existing_subscription(topic_arn, endpoint)
      next_token = nil
      loop do
        response = @sns.list_subscriptions_by_topic(
          topic_arn: topic_arn,
          next_token: next_token
        )
        match = response.subscriptions.find { |s|
          s.protocol == "https" && s.endpoint == endpoint
        }
        return match.subscription_arn if match
        next_token = response.next_token
        break if next_token.blank?
      end
      nil
    end

    # Persist ARNs onto Team::SesConfiguration so the SNS webhook can route
    # incoming notifications back to this team via `config_for_topic`.
    # `update_columns` skips validations/callbacks — fine here since we're
    # writing AWS-derived values, not user input.
    def persist_topic_arns
      attrs = {}
      TOPICS.each do |kind, meta|
        arn = @summary.dig(:topics, kind, :arn)
        attrs[meta[:attribute]] = arn if arn.present?
      end
      attrs[:configuration_set_name] = CONFIGURATION_SET_NAME if @team.ses_configuration.configuration_set_name.blank?
      return if attrs.empty?
      begin
        @team.ses_configuration.update_columns(attrs)
      rescue ActiveRecord::StatementInvalid => e
        # Most likely the sns_delivery_topic_arn migration hasn't run yet.
        # Retry without the unknown column so we still persist what we can.
        attrs.delete(:sns_delivery_topic_arn)
        @team.ses_configuration.update_columns(attrs) if attrs.any?
        @errors << "persist: #{e.message}"
      end
    end

    # Configuration set event destinations are a single named resource
    # that fans out to multiple SNS topics — except SES only allows ONE
    # SNS topic per event destination. So for three event types routed to
    # three different topics, we need three event destinations (one per
    # topic). Naming: "lewsnetter-events-bounce", etc.
    #
    # Create vs Update: CreateConfigurationSetEventDestination raises
    # AlreadyExists if the named destination is there; we then call
    # UpdateConfigurationSetEventDestination to keep it in sync.
    def ensure_event_destination
      results = {}
      TOPICS.each do |kind, meta|
        topic_arn = @summary.dig(:topics, kind, :arn)
        next if topic_arn.blank?

        destination_name = "#{EVENT_DESTINATION_NAME}-#{kind}"
        destination_payload = {
          enabled: true,
          matching_event_types: [meta[:event_type]],
          sns_destination: {topic_arn: topic_arn}
        }

        begin
          @ses.create_configuration_set_event_destination(
            configuration_set_name: CONFIGURATION_SET_NAME,
            event_destination_name: destination_name,
            event_destination: destination_payload
          )
          results[kind] = {name: destination_name, action: :created, error: nil}
        rescue Aws::SESV2::Errors::AlreadyExistsException
          begin
            @ses.update_configuration_set_event_destination(
              configuration_set_name: CONFIGURATION_SET_NAME,
              event_destination_name: destination_name,
              event_destination: destination_payload
            )
            results[kind] = {name: destination_name, action: :updated, error: nil}
          rescue Aws::SESV2::Errors::ServiceError => e
            @errors << "event_destination[#{kind}]: #{e.message}"
            results[kind] = {name: destination_name, action: nil, error: e.message}
          end
        rescue Aws::SESV2::Errors::ServiceError => e
          @errors << "event_destination[#{kind}]: #{e.message}"
          results[kind] = {name: destination_name, action: nil, error: e.message}
        end
      end
      @summary[:event_destination] = {name: EVENT_DESTINATION_NAME, destinations: results}
    end
  end
end
