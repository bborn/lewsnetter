# frozen_string_literal: true

require "test_helper"

module Chats
  class ToolAdapterTest < ActiveSupport::TestCase
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
    end

    # The in-app agent must see the same argument schema an external MCP
    # client gets from tools/list. Anything else is a declaration the model
    # follows and Mcp::Tool::Base#invoke then rejects (or worse, accepts).
    test "every tool declares the schema the MCP server publishes" do
      Mcp::Tool::Loader.load_all.each do |tool_class|
        published = Mcp::Server.wrap(tool_class).input_schema_to_json
        declared = adapted_schema(tool_class)

        assert_equal published.deep_stringify_keys, declared,
          "#{tool_class.tool_name}: the agent's declaration differs from tools/list"
      end
    end

    # The agent sends every tool on every request, and Anthropic answers a
    # single invalid schema with a 400, so one typo would break every chat.
    test "every tool's schema is valid JSON Schema" do
      metaschema = JSON::Validator.validator_for_name("draft4").metaschema

      Mcp::Tool::Loader.load_all.each do |tool_class|
        errors = JSON::Validator.fully_validate(metaschema, adapted_schema(tool_class))

        assert_empty errors, "#{tool_class.tool_name}: #{errors.first}"
      end
    end

    test "subscribers_bulk_upsert declares records as objects that need an email" do
      records = adapted_schema(Mcp::Tools::Subscribers::BulkUpsert).dig("properties", "records")

      assert_equal "array", records["type"]
      assert_equal "object", records.dig("items", "type")
      assert_equal ["email"], records.dig("items", "required")
      assert_equal true, records.dig("items", "additionalProperties")
      assert_equal "object", records.dig("items", "properties", "custom_attributes", "type")
    end

    test "union and nullable types keep every member instead of collapsing to string" do
      import = adapted_schema(Mcp::Tools::Sequences::ImportIntercom)
      assert_equal %w[object string], import.dig("properties", "series_json", "type")
      assert_equal true, import.dig("properties", "dry_run", "default")

      update = adapted_schema(Mcp::Tools::Sequences::Update)
      assert_equal %w[integer null], update.dig("properties", "exit_segment_id", "type")
      assert_equal 1, update.dig("properties", "reentry_days", "minimum")
      assert_equal ::Sequence::STATUSES, update.dig("properties", "status", "enum")
    end

    test "an unknown or missing property type is passed through, not declared as string" do
      tool = fake_tool(
        type: "object",
        properties: {
          anything: {description: "no type given"},
          odd: {type: "uuid"}
        }
      )
      properties = adapted_schema(tool)["properties"]

      assert_equal({"description" => "no type given"}, properties["anything"])
      assert_equal({"type" => "uuid"}, properties["odd"])
    end

    test "a tool without an arguments schema declares an empty object, like the MCP server" do
      schema = adapted_schema(fake_tool(nil))

      assert_equal({"type" => "object", "properties" => {}}, schema)
    end

    test "the wire name stays the MCP tool name" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Subscribers::BulkUpsert, context: @ctx)

      assert_equal "subscribers_bulk_upsert", adapted.new.name
    end

    test "execution still validates against the schema server-side" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Subscribers::BulkUpsert, context: @ctx).new

      result = adapted.call("records" => [{"name" => "No email"}])

      assert_match(/\AInvalid arguments: .*email/, result[:error])
      assert_equal 0, @team.subscribers.count
    end

    # The agent reports a failed tool the way the MCP server does
    # (Mcp::Server.tool_error), so the model never sees SQL, paths or
    # exception classes, and the failure shows up in the log.
    test "an unexpected error is logged and the model gets a short message" do
      tool = Mcp::Tools::Team::GetCurrent
      original = tool.instance_method(:call)
      tool.define_method(:call) { |**| raise "boom at /srv/app/secret.rb" }
      adapted = ToolAdapter.adapt(tool, context: @ctx).new

      result = nil
      log = capture_log { result = adapted.call }

      assert_equal({error: "Tool failed. The error has been logged."}, result)
      assert_match(/tool=team_get_current failed: RuntimeError: boom at/, log)
    ensure
      tool.define_method(:call, original)
    end

    test "a missing record names the model without the query" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Subscribers::Get, context: @ctx).new

      assert_equal({error: "Subscriber not found"}, adapted.call("id" => 999_999))
    end

    test "a validation failure keeps its message without the exception class" do
      adapted = ToolAdapter.adapt(Mcp::Tools::Segments::Create, context: @ctx).new

      assert_equal({error: "Validation failed: Name can't be blank"}, adapted.call("name" => ""))
    end

    test "a refused ability keeps the role message" do
      member = create(:onboarded_user)
      create(:membership, team: @team, user: member)
      sub = @team.subscribers.create!(email: "keep@example.com", subscribed: true)
      ctx = Mcp::Tool::Context.new(user: member, team: @team)
      adapted = ToolAdapter.adapt(Mcp::Tools::Subscribers::Delete, context: ctx).new

      assert_equal({error: Mcp::Tool::Base::NOT_ALLOWED}, adapted.call("id" => sub.id))
      assert Subscriber.exists?(sub.id)
    end

    test "execution runs against the context's team" do
      other_team = create(:onboarded_user).current_team
      adapted = ToolAdapter.adapt(Mcp::Tools::Subscribers::BulkUpsert, context: @ctx).new

      result = adapted.call("records" => [{"email" => "ada@example.com", "custom_attributes" => {"plan" => "pro"}}])

      assert_equal 1, result[:created]
      assert_equal "pro", @team.subscribers.find_by!(email: "ada@example.com").custom_attributes["plan"]
      assert_equal 0, other_team.subscribers.count
    end

    private

    def capture_log
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      original = Rails.logger
      Rails.logger = logger
      yield
      io.string
    ensure
      Rails.logger = original
    end

    def adapted_schema(tool_class)
      ToolAdapter.adapt(tool_class, context: @ctx).new.parameters_schema
    end

    # A stand-in tool class that is not an Mcp::Tool::Base subclass, so it
    # never joins Base.descendants and the registry other tests load.
    def fake_tool(schema)
      Class.new do
        define_singleton_method(:tool_name) { "fake_tool" }
        define_singleton_method(:description) { "A fake tool" }
        define_singleton_method(:arguments_schema) { schema }
      end
    end

    def agent_tool(name)
      Chats::ToolAdapter.adapt_all(context: @ctx).map(&:new).find { |tool| tool.name == name }
    end

    def llm_call(name, arguments)
      RubyLLM::ToolCall.new(id: "call_1", name: name, arguments: arguments)
    end

    test "adapt_all leaves out tools hidden from the in-app agent" do
      user = create(:onboarded_user)
      ctx = Mcp::Tool::Context.new(user: user, team: user.current_team)
      names = Chats::ToolAdapter.adapt_all(context: ctx).map { |t| t.new.name }

      assert_includes names, "campaigns_send_test"
      refute_includes names, "campaigns_send_now"
      refute_includes names, "campaigns_schedule"
      refute_includes names, "campaigns_resume_send"
    end

    # The calls the user approves in the chat panel before they run.
    APPROVED_TOOLS = %w[
      campaigns_delete email_templates_delete segments_delete subscribers_delete sequences_set_enabled
    ].freeze

    test "deletes and turning Sequences on or off wait for approval" do
      APPROVED_TOOLS.each do |name|
        assert agent_tool(name).requires_approval?(llm_call(name, "id" => 1, "enabled" => true)), "#{name} should ask first"
      end
    end

    test "sequences_update asks only when it activates a sequence" do
      tool = agent_tool("sequences_update")

      assert tool.requires_approval?(llm_call("sequences_update", "id" => 1, "status" => "active"))
      assert_not tool.requires_approval?(llm_call("sequences_update", "id" => 1, "status" => "paused"))
      assert_not tool.requires_approval?(llm_call("sequences_update", id: 1, name: "Renamed"))
    end

    test "other tools run without asking" do
      tools = Chats::ToolAdapter.adapt_all(context: @ctx).map(&:new)
      asking = tools.select { |tool| tool.requires_approval?(llm_call(tool.name, "id" => 1, "status" => "active", "enabled" => true)) }

      assert_equal (APPROVED_TOOLS + ["sequences_update"]).sort, asking.map(&:name).sort
    end

    test "the approval line names the record the call would change" do
      campaign = create(:campaign, team: @team, subject: "Spring launch")
      other_team = create(:onboarded_user).current_team
      hidden = create(:campaign, team: other_team, subject: "Not yours")

      assert_equal %(Delete campaign "Spring launch" (##{campaign.id})),
        Chats::ToolAdapter.approval_summary(llm_call("campaigns_delete", "id" => campaign.id), context: @ctx)
      assert_equal "Delete campaign ##{hidden.id}",
        Chats::ToolAdapter.approval_summary(llm_call("campaigns_delete", "id" => hidden.id), context: @ctx)
    end
  end
end
