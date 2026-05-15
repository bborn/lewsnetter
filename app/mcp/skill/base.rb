# frozen_string_literal: true

require "yaml"

module Mcp
  module Skill
    # One parsed skill: frontmatter (name, description, when_to_use) plus the
    # raw markdown body (which may contain ERB). Rendering happens elsewhere
    # (Mcp::Skill::Renderer) so that Base instances are pure data and safe to
    # cache between requests.
    class Base
      class InvalidFormat < StandardError; end

      FRONTMATTER_PATTERN = /\A---\n(.*?)\n---\n(.*)\z/m

      attr_reader :name, :description, :when_to_use, :raw_body, :source_path

      def self.parse(text, source_path: nil)
        match = text.match(FRONTMATTER_PATTERN)
        raise InvalidFormat, "missing frontmatter" unless match

        front = YAML.safe_load(match[1])
        body = match[2].sub(/\A\n+/, "")

        name = front["name"]
        raise InvalidFormat, "missing 'name'" if name.to_s.strip.empty?

        new(
          name: name,
          description: front["description"].to_s,
          when_to_use: front["when_to_use"].to_s,
          raw_body: body,
          source_path: source_path
        )
      end

      def self.load(path)
        parse(File.read(path), source_path: path.to_s)
      end

      def initialize(name:, description:, when_to_use:, raw_body:, source_path: nil)
        @name = name
        @description = description
        @when_to_use = when_to_use
        @raw_body = raw_body
        @source_path = source_path
        freeze
      end

      def uri
        "skill://#{name}"
      end
    end
  end
end
