# frozen_string_literal: true

require "test_helper"

module Mcp
  class TelemetryTest < ActiveSupport::TestCase
    test "log_invocation emits a [mcp] tagged structured line" do
      log_io = StringIO.new
      logger = Logger.new(log_io)
      Telemetry.with_logger(logger) do
        Telemetry.log_invocation(tool_name: "team_get_current", team_id: 7, latency_ms: 12, success: true)
      end
      assert_match(/\[mcp\]/, log_io.string)
      assert_match(/tool=team_get_current/, log_io.string)
      assert_match(/team_id=7/, log_io.string)
      assert_match(/latency_ms=12/, log_io.string)
      assert_match(/success=true/, log_io.string)
    end

    test "log_invocation with error_class includes error key" do
      log_io = StringIO.new
      Telemetry.with_logger(Logger.new(log_io)) do
        Telemetry.log_invocation(tool_name: "x", team_id: 1, latency_ms: 1, success: false, error_class: "ActiveRecord::RecordNotFound")
      end
      assert_match(/error=ActiveRecord::RecordNotFound/, log_io.string)
    end

    test "around wraps a block, times it, logs success on normal return" do
      log_io = StringIO.new
      result = Telemetry.with_logger(Logger.new(log_io)) do
        Telemetry.around(tool_name: "fake_tool", team_id: 42) { 99 }
      end
      assert_equal 99, result
      assert_match(/tool=fake_tool/, log_io.string)
      assert_match(/team_id=42/, log_io.string)
      assert_match(/success=true/, log_io.string)
    end

    test "around logs failure and re-raises on exception" do
      log_io = StringIO.new
      assert_raises(RuntimeError) do
        Telemetry.with_logger(Logger.new(log_io)) do
          Telemetry.around(tool_name: "boom", team_id: 1) { raise "kaboom" }
        end
      end
      assert_match(/tool=boom/, log_io.string)
      assert_match(/success=false/, log_io.string)
      assert_match(/error=RuntimeError/, log_io.string)
    end
  end
end
