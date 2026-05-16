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
    # that's appeared at least once. For each key, infer the best value type
    # from observed values (array, number, boolean, or string) so the UI can
    # show the right operator catalog. Sample size is bounded so this stays
    # cheap for large teams.
    def sample_custom_attribute_fields(table, key_prefix)
      sample = @team.send(table).where.not(custom_attributes: {}).limit(200).pluck(:custom_attributes)

      # Bucket observed values by key → list of values seen.
      observed = Hash.new { |h, k| h[k] = [] }
      sample.each do |row|
        next unless row.is_a?(Hash)
        row.each { |k, v| observed[k] << v }
      end

      observed.keys.sort.map do |attr|
        type = infer_type(observed[attr])
        {key: "#{key_prefix}#{attr}", label: attr, type: type}
      end
    end

    # Best-effort: if any observed value is an array → :array (it dominates).
    # Then check uniform booleans / numbers; if observed strings all look
    # like CSVs (comma-separated, no spaces around commas, more than one
    # segment), pick :csv_list so the UI surfaces element-wise operators
    # that won't false-positive ("brand" matching "brand_account"). Fall
    # back to :string.
    def infer_type(values)
      non_null = values.reject(&:nil?)
      return :string  if non_null.empty?
      return :array   if non_null.any? { |v| v.is_a?(Array) }
      return :boolean if non_null.all? { |v| v == true || v == false }
      return :number  if non_null.all? { |v| v.is_a?(Numeric) }
      return :csv_list if non_null.all? { |v| csv_shaped?(v) }
      :string
    end

    # A value is "CSV-shaped" if it's a string with 2+ non-empty segments
    # split on comma, and the segments don't have surrounding whitespace
    # (which would suggest natural language like "Hello, world").
    def csv_shaped?(value)
      return false unless value.is_a?(String) && value.include?(",")
      segments = value.split(",")
      return false if segments.length < 2
      segments.all? { |s| s.length.positive? && s == s.strip }
    end
  end
end
