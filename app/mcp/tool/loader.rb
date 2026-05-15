# frozen_string_literal: true

module Mcp
  module Tool
    # Enumerates app/mcp/tools/**/*.rb, forces each to load (so Zeitwerk
    # registers the constant and inherited() fires), and returns the
    # full set of Mcp::Tool::Base descendants. Idempotent.
    module Loader
      module_function

      def load_all
        Dir.glob(Rails.root.join("app/mcp/tools/**/*.rb")).each do |path|
          # Use the Zeitwerk autoloader to force-load each tool file.
          # require_dependency is deprecated in Rails 7+ and removed in 8.x.
          # load_file is idempotent within a single autoloader — safe to call
          # multiple times (subsequent calls are no-ops once the constant is
          # already registered).
          Rails.autoloaders.main.load_file(path)
        end
        Mcp::Tool::Base.descendants.sort_by(&:tool_name)
      end
    end
  end
end
