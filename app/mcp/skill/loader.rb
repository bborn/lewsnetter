# frozen_string_literal: true

module Mcp
  module Skill
    # Enumerates app/mcp/skills/*.md, parses each via Skill::Base.load,
    # returns an array sorted by name. Idempotent.
    module Loader
      module_function

      def load_all
        Dir.glob(Rails.root.join("app/mcp/skills/*.md")).sort.map { |path| Base.load(path) }
      end
    end
  end
end
