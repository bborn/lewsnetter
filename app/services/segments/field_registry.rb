# frozen_string_literal: true

module Segments
  # Builds the UI-side list of fields a user can pick from in the segment
  # builder: built-in subscriber/company columns + the team's observed
  # custom_attribute keys (sampled live from the data).
  #
  # Returns a hash:
  #   {
  #     "Subscriber" => [
  #       {key: "subscribers.email", label: "Email", type: :string},
  #       ...
  #     ],
  #     "Subscriber custom attributes" => [
  #       {key: "custom_attributes.plan", label: "plan", type: :string},
  #       ...
  #     ],
  #     "Company" => [...],
  #     "Company custom attributes" => [...]
  #   }
  class FieldRegistry
    def initialize(team:)
      @team = team
    end

    def call
      {
        "Subscriber" => builtin_subscriber_fields,
        "Subscriber custom attributes" => sample_custom_attribute_fields(:subscribers, "custom_attributes."),
        "Company" => builtin_company_fields,
        "Company custom attributes" => sample_custom_attribute_fields(:companies, "company_attributes.")
      }.reject { |_, fields| fields.blank? }
    end

    # Operator catalog for a value type — what the UI shows in the operator
    # picker once a field is chosen. Source of truth: PredicateCompiler::OPERATORS.
    def self.operators_for(type)
      PredicateCompiler::OPERATORS[type.to_sym] || []
    end

    private

    def builtin_subscriber_fields
      PredicateCompiler::FIELDS.select { |k, _| k.start_with?("subscribers.") }.map do |key, meta|
        {key: key, label: meta[:label], type: meta[:type]}
      end
    end

    def builtin_company_fields
      PredicateCompiler::FIELDS.select { |k, _| k.start_with?("companies.") }.map do |key, meta|
        {key: key, label: meta[:label], type: meta[:type]}
      end
    end

    # Sample up to 200 rows from the named table and surface every JSON key
    # that's appeared at least once. Sample size is bounded so this stays
    # cheap for large teams.
    def sample_custom_attribute_fields(table, key_prefix)
      sample = @team.send(table).where.not(custom_attributes: {}).limit(200).pluck(:custom_attributes)
      keys = sample.flat_map { |row| row.is_a?(Hash) ? row.keys : [] }.uniq.sort

      keys.map { |attr| {key: "#{key_prefix}#{attr}", label: attr, type: :string} }
    end
  end
end
