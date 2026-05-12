require "active_support/concern"

module Lewsnetter
  # Mixin providing `acts_as_lewsnetter_subscriber` on ActiveRecord models.
  #
  #   class User < ApplicationRecord
  #     acts_as_lewsnetter_subscriber(
  #       external_id: :id,
  #       email: :email,
  #       name: :full_name,
  #       attributes: ->(u) { { plan: u.plan_tier } }
  #     )
  #   end
  module Subscriber
    extend ActiveSupport::Concern

    module ClassMethods
      def acts_as_lewsnetter_subscriber(external_id: :id, email: :email, name: nil, attributes: nil, subscribed: nil)
        @lewsnetter_subscriber_config = {
          external_id: external_id,
          email: email,
          name: name,
          attributes: attributes,
          subscribed: subscribed
        }

        include Lewsnetter::Subscriber::InstanceMethods

        after_commit :sync_to_lewsnetter!, on: [:create, :update]
        after_commit :delete_from_lewsnetter!, on: :destroy
      end

      def lewsnetter_subscriber_config
        @lewsnetter_subscriber_config
      end
    end

    module InstanceMethods
      # Build the payload hash this record would send.
      def lewsnetter_payload
        cfg = self.class.lewsnetter_subscriber_config or
          raise Lewsnetter::ConfigurationError, "acts_as_lewsnetter_subscriber not called on #{self.class}"

        payload = {
          external_id: resolve_lewsnetter_value(cfg[:external_id]).to_s,
          email: resolve_lewsnetter_value(cfg[:email]),
          name: resolve_lewsnetter_value(cfg[:name]),
          attributes: resolve_lewsnetter_attributes(cfg[:attributes])
        }
        subscribed = resolve_lewsnetter_value(cfg[:subscribed])
        payload[:subscribed] = subscribed unless subscribed.nil?
        payload
      end

      # Enqueue (or run inline if config.async == false) the SyncJob.
      def sync_to_lewsnetter!
        payload = lewsnetter_payload
        if Lewsnetter.configuration.async
          Lewsnetter::SyncJob.perform_later(payload)
        else
          Lewsnetter::SyncJob.new.perform(payload)
        end
      end

      # Delete from Lewsnetter (GDPR-style hard delete) on destroy.
      def delete_from_lewsnetter!
        cfg = self.class.lewsnetter_subscriber_config
        external_id = resolve_lewsnetter_value(cfg[:external_id]).to_s
        if Lewsnetter.configuration.async
          Lewsnetter::SyncJob.perform_later({external_id: external_id, _delete: true})
        else
          Lewsnetter.client.delete_subscriber(external_id)
        end
      end

      private

      def resolve_lewsnetter_value(spec)
        case spec
        when nil then nil
        when Symbol then respond_to?(spec) ? public_send(spec) : nil
        when Proc then spec.call(self)
        else spec
        end
      end

      def resolve_lewsnetter_attributes(spec)
        attrs = {}
        if Lewsnetter.configuration.default_attributes_proc
          attrs.merge!(Lewsnetter.configuration.default_attributes_proc.call(self).to_h)
        end
        case spec
        when nil then attrs.empty? ? nil : attrs
        when Symbol then attrs.merge((respond_to?(spec) ? public_send(spec) : {}).to_h)
        when Proc then attrs.merge(spec.call(self).to_h)
        when Hash then attrs.merge(spec)
        else attrs
        end
      end
    end
  end
end
