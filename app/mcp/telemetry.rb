# frozen_string_literal: true

module Mcp
  # Structured logging for every MCP tool invocation. One line per call,
  # prefixed `[mcp]`, with key=value pairs:
  #   [mcp] tool=<name> team_id=<id> latency_ms=<int> success=<bool> [error=<class>]
  # Cheap enough to leave on in production. Future analytics piping can grep
  # on `[mcp]` and parse the kv pairs.
  module Telemetry
    module_function

    def with_logger(logger)
      previous = Thread.current[:mcp_telemetry_logger]
      Thread.current[:mcp_telemetry_logger] = logger
      yield
    ensure
      Thread.current[:mcp_telemetry_logger] = previous
    end

    def log_invocation(tool_name:, team_id:, latency_ms:, success:, error_class: nil)
      logger = Thread.current[:mcp_telemetry_logger] || Rails.logger
      parts = ["[mcp]", "tool=#{tool_name}", "team_id=#{team_id}", "latency_ms=#{latency_ms}", "success=#{success}"]
      parts << "error=#{error_class}" if error_class
      logger.info(parts.join(" "))
    end

    # Wraps a block, times it, logs an invocation, returns the block's value.
    # Re-raises any exception from the block (after logging).
    def around(tool_name:, team_id:)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      log_invocation(tool_name: tool_name, team_id: team_id, latency_ms: latency_ms, success: true)
      result
    rescue => e
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      log_invocation(tool_name: tool_name, team_id: team_id, latency_ms: latency_ms, success: false, error_class: e.class.name)
      raise
    end
  end
end
