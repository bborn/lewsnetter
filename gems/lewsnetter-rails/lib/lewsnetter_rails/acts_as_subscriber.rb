# frozen_string_literal: true

module LewsnetterRails
  # Mixin for the source app's user-like model. Mirrors the intercom-rails
  # pattern: declare which mapper turns a record into a Lewsnetter payload,
  # and after_commit will enqueue a sync job. Destroys enqueue a delete.
  #
  # Usage in the source app's model:
  #
  #   class User < ApplicationRecord
  #     include LewsnetterRails::ActsAsSubscriber
  #     acts_as_lewsnetter_subscriber mapper: "Lewsnetter::UserMapper"
  #   end
  #
  # And a mapper that converts a User to the Lewsnetter payload shape:
  #
  #   class Lewsnetter::UserMapper
  #     def self.call(user)
  #       {
  #         external_id: user.id.to_s,
  #         email:       user.email,
  #         name:        user.full_name,
  #         subscribed:  !user.email_opt_out?,
  #         attributes: {
  #           tenant_type:        user.tenant_type,        # "brand" | "events" | "influencer"
  #           tabs_enabled:       user.tabs_enabled,       # array — Lewsnetter normalizes CSV too
  #           plan:               user.plan,
  #           subdomain:          user.subdomain,
  #           intercom_signed_up_at: user.created_at,
  #           # ...whatever you want to segment on
  #         }
  #       }
  #     end
  #   end
  module ActsAsSubscriber
    extend ActiveSupport::Concern

    class_methods do
      def acts_as_lewsnetter_subscriber(mapper:, only_if: nil)
        cattr_accessor :lewsnetter_mapper
        cattr_accessor :lewsnetter_only_if
        self.lewsnetter_mapper  = mapper
        self.lewsnetter_only_if = only_if

        after_commit :enqueue_lewsnetter_sync,   on: %i[create update]
        after_commit :enqueue_lewsnetter_delete, on: :destroy
      end
    end

    def enqueue_lewsnetter_sync
      return unless LewsnetterRails.configuration.enabled
      return if lewsnetter_only_if && !instance_exec(&lewsnetter_only_if)
      LewsnetterRails::SyncJob.perform_later(
        model_class: self.class.name,
        id: id,
        mapper: lewsnetter_mapper
      )
    end

    def enqueue_lewsnetter_delete
      return unless LewsnetterRails.configuration.enabled
      LewsnetterRails::Client.new.delete(external_id: id.to_s)
    rescue LewsnetterRails::TransportError => e
      LewsnetterRails.configuration.logger&.warn("[LewsnetterRails] delete failed for #{self.class.name}##{id}: #{e.message}")
    end
  end
end
