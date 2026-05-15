# frozen_string_literal: true

require "test_helper"

module Mcp
  module Skill
    class LoaderTest < ActiveSupport::TestCase
      test ".load_all returns Base instances for every skill in app/mcp/skills" do
        skills = Loader.load_all
        assert_kind_of Array, skills
        assert(skills.all? { |s| s.is_a?(Base) })
      end

      test "skill names are unique" do
        names = Loader.load_all.map(&:name)
        duplicates = names.tally.select { |_, c| c > 1 }.keys
        assert_empty duplicates, "Duplicate skill names: #{duplicates.inspect}"
      end

      test "every skill has a non-empty description and when_to_use" do
        Loader.load_all.each do |s|
          refute s.description.strip.empty?, "#{s.name} missing description"
          refute s.when_to_use.strip.empty?, "#{s.name} missing when_to_use"
        end
      end
    end
  end
end
