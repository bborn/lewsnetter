# frozen_string_literal: true

module Subscribers
  # Normalizes custom_attributes on the way in. Source apps (Intercom, IK,
  # CSV imports) often ship list-like attributes as comma-separated strings
  # — e.g. "billing,brand_account,influencer_hub" — because that's how
  # they're stored upstream. We'd rather have them as JSON arrays so our
  # segment builder can do safe element-wise matching ("brand" won't
  # accidentally match "brand_account").
  #
  # We only transform keys whose names strongly suggest lists. A free-form
  # rule (e.g. "any string with a comma") would silently mangle natural
  # language values like "Acme, Inc." or country lists. The explicit
  # allowlist keeps surprises out.
  #
  # Used by the API bulk endpoint, the MCP bulk_upsert tool, and the CSV
  # import job — all the boundaries where third-party data crosses into
  # Lewsnetter.
  class AttributeNormalizer
    # Suffix-based detection: any key ending in one of these gets the
    # CSV→array treatment. Add new suffixes here as new patterns appear
    # in source data.
    LIST_LIKE_SUFFIXES = %w[
      _enabled
      _tags
      _list
      _ids
      tabs
    ].freeze

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.is_a?(Hash) ? attrs.dup : {}
    end

    def call
      @attrs.each_with_object({}) do |(k, v), out|
        out[k] = list_like_key?(k) ? coerce_to_array(v) : v
      end
    end

    private

    def list_like_key?(key)
      key_str = key.to_s
      LIST_LIKE_SUFFIXES.any? { |suffix| key_str.end_with?(suffix) }
    end

    # Already an array → pass through.
    # CSV-shaped string ("a,b,c" with no spaces around commas) → split.
    # Anything else → leave alone (we'd rather pass through unknown shapes
    # than mangle data the user might be relying on).
    def coerce_to_array(value)
      return value if value.is_a?(Array)
      return value unless value.is_a?(String)
      return value unless value.include?(",")
      segments = value.split(",")
      return value if segments.any? { |s| s.empty? || s != s.strip }
      segments
    end
  end
end
