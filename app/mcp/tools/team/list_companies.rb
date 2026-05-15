# frozen_string_literal: true

module Mcp
  module Tools
    module Team
      class ListCompanies < Mcp::Tool::Base
        tool_name "team_list_companies"
        description "Lists companies on the calling team. Supports pagination and a query that matches name or external_id."
        arguments_schema(
          type: "object",
          additionalProperties: false,
          properties: {
            limit: {type: "integer", minimum: 1, maximum: 200, default: 50},
            offset: {type: "integer", minimum: 0, default: 0},
            query: {type: "string"}
          }
        )

        def call(arguments:, context:)
          scope = context.team.companies
          if (q = arguments["query"]).present?
            like = "%#{q}%"
            scope = scope.where("name LIKE ? OR external_id LIKE ?", like, like)
          end
          total = scope.count
          limit = arguments["limit"] || 50
          offset = arguments["offset"] || 0
          rows = scope.order(:id).limit(limit).offset(offset).map { |c| serialize(c) }
          {companies: rows, total: total, limit: limit, offset: offset}
        end

        private

        def serialize(company)
          {
            id: company.id,
            name: company.name,
            external_id: company.external_id,
            custom_attributes: company.custom_attributes || {},
            subscriber_count: company.subscribers.count,
            created_at: company.created_at.iso8601,
            updated_at: company.updated_at.iso8601
          }
        end
      end
    end
  end
end
