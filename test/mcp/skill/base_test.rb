# frozen_string_literal: true

require "test_helper"

module Mcp
  module Skill
    class BaseTest < ActiveSupport::TestCase
      SAMPLE = <<~MD
        ---
        name: example-skill
        description: A demonstration skill
        when_to_use: When the user asks for an example
        ---

        # Hello

        Body text here, with <%= 1 + 1 %> ERB tag.
      MD

      test ".parse pulls frontmatter and body" do
        skill = Base.parse(SAMPLE)
        assert_equal "example-skill", skill.name
        assert_equal "A demonstration skill", skill.description
        assert_equal "When the user asks for an example", skill.when_to_use
        assert_match(/^# Hello/, skill.raw_body)
        assert_match(/<%= 1 \+ 1 %>/, skill.raw_body)
      end

      test ".parse raises if frontmatter is missing" do
        assert_raises(Base::InvalidFormat) { Base.parse("just markdown, no frontmatter") }
      end

      test ".parse raises if name is missing" do
        body = "---\ndescription: x\nwhen_to_use: y\n---\n\nbody"
        assert_raises(Base::InvalidFormat) { Base.parse(body) }
      end

      test ".load reads a file and parses it" do
        path = Rails.root.join("tmp/test_skill.md")
        File.write(path, SAMPLE)
        skill = Base.load(path)
        assert_equal "example-skill", skill.name
      ensure
        File.delete(path) if File.exist?(path)
      end

      test "#uri returns skill://<name>" do
        skill = Base.parse(SAMPLE)
        assert_equal "skill://example-skill", skill.uri
      end
    end
  end
end
