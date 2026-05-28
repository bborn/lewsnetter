# frozen_string_literal: true

module Mcp
  module Tools
    module Subscribers
      class List < Mcp::Tool::Base
        include Mcp::Tools::Serializers

        tool_name "subscribers_list"
        description "Lists subscribers on the calling team. Supports limit, offset, subscribed filter, and a query that matches email (exact), name (substring), or external_id (substring)."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0},
            subscribed: {type: "boolean"},
            query: {type: "string"}
          }
        )

        def call(arguments:, context:)
          scope = context.team.subscribers
          scope = scope.where(subscribed: arguments["subscribed"]) if arguments.key?("subscribed")
          if (q = arguments["query"]).present?
            # Email is deterministic-encrypted, so we can only do exact-match
            # on it (LIKE against ciphertext is meaningless). Name and
            # external_id are plaintext, so substring LIKE works.
            like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
            exact_email_ids = scope.where(email: q).pluck(:id)
            name_ids = scope.where("name LIKE ?", like).pluck(:id)
            external_id_ids = scope.where("external_id LIKE ?", like).pluck(:id)
            scope = scope.where(id: (exact_email_ids + name_ids + external_id_ids).uniq)
          end
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.order(:id).limit(limit).offset(offset).map { |s| serialize_subscriber(s) }
          {subscribers: rows, total: total, limit: limit, offset: offset}
        end
      end
    end
  end
end
