# frozen_string_literal: true

# Samples a team's subscribers' custom_attributes JSON and returns a
# `{key => "type1|type2"}` hash describing the observed schema. Used by
# the AI services (drafter, segment translator, post-send analyst) to
# ground prompts in the team's actual data shape, and by the MCP
# `team_custom_attribute_schema` tool so external agents can do the same.
class Team
  class CustomAttributeSchema
    def initialize(team:, limit: 50)
      @team = team
      @limit = limit
    end

    def call
      return {sample: {}, sample_size: 0} unless @team
      rows = @team.subscribers.where.not(custom_attributes: {}).limit(@limit).pluck(:custom_attributes)
      keys = Hash.new { |h, k| h[k] = Set.new }
      rows.each do |row|
        next unless row.is_a?(Hash)
        row.each { |k, v| keys[k] << infer_type(v) }
      end
      {sample: keys.transform_values { |types| types.to_a.join("|") }, sample_size: rows.size}
    end

    private

    def infer_type(value)
      case value
      when TrueClass, FalseClass then "boolean"
      when Integer then "integer"
      when Float then "number"
      when Array then "array"
      when Hash then "object"
      when nil then "null"
      else "string"
      end
    end
  end
end
