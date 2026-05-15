# MCP Server Chassis Implementation Plan (Phase 1 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up an authenticated MCP server endpoint at `POST /mcp` with one working tool (`team.get_current`), end-to-end tested, so Phases 2–6 can land tools/skills/agent on a known-good chassis.

**Architecture:** A `fast-mcp`-backed Rack endpoint mounted at `/mcp`. A custom Rack middleware (`Mcp::DoorkeeperAuth`) validates `Authorization: Bearer <token>` against `Doorkeeper::AccessToken` and stuffs `current_user` + `current_team` into the Rack env. A `Mcp::Tool::Base` class + `Mcp::Tool::Loader` enumerate `app/mcp/tools/**/*.rb` at boot and register each with the server. One trivial tool ships in this phase to prove the wiring.

**Tech Stack:** Rails 8.1, `fast-mcp` (~> 1.5), `doorkeeper` (already installed via BulletTrain), Minitest + FactoryBot (existing test stack).

**Reference spec:** `docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md`

**Out of scope for this plan:** Raw API tools (Phase 2), skills (Phase 3), `Llm::Configuration` + LLM tools (Phase 4), in-app agent (Phase 5), cross-linking existing AI panels (Phase 6). Each gets its own plan.

---

## Pre-flight

The plan assumes you start at `master` HEAD with no uncommitted changes you care about. The session-start working tree had unrelated theme partial mods; **stash or commit those before starting** so each task's diff stays scoped.

```
git status                   # if dirty, deal with it before proceeding
bundle exec rails -v         # should print Rails 8.1.x
```

---

## File structure (this phase)

**Created:**
- `Gemfile` — add `gem "fast-mcp"`
- `app/mcp/tool/base.rb` — abstract base for tools
- `app/mcp/tool/loader.rb` — enumerates `app/mcp/tools/**/*.rb` and registers each
- `app/mcp/tool/context.rb` — value object passed to `#call(arguments:, context:)`
- `app/mcp/tools/team/get_current.rb` — first concrete tool
- `app/mcp/doorkeeper_auth.rb` — Rack middleware
- `app/mcp/server.rb` — wires tools into the `FastMcp::Server` instance
- `config/initializers/mcp.rb` — boot-time loader
- `test/mcp/tool/base_test.rb`
- `test/mcp/tool/loader_test.rb`
- `test/mcp/doorkeeper_auth_test.rb`
- `test/mcp/tools/team/get_current_test.rb`
- `test/mcp/server_integration_test.rb` — full HTTP roundtrip

**Modified:**
- `Gemfile.lock` — `bundle install` output
- `config/routes.rb` — mount `/mcp` (Rack endpoint, before authenticated routes)
- `config/application.rb` — add `app/mcp` to autoload paths

---

## Task 1: Add `fast-mcp` gem

**Files:**
- Modify: `/Users/bruno/Projects/rails/lewsnetter/Gemfile` (append near other API/integration gems)

- [ ] **Step 1: Add the gem line**

Find the section in `Gemfile` near `gem "doorkeeper"` (around the BulletTrain block). Append immediately after the doorkeeper line (or in the section that holds API gems):

```ruby
# MCP (Model Context Protocol) server. Mounted at /mcp via a Rack endpoint
# in routes.rb; auth handled by Mcp::DoorkeeperAuth middleware.
gem "fast-mcp", "~> 1.5"
```

If `gem "doorkeeper"` is not in `Gemfile` (it's a BulletTrain transitive dep), add the `fast-mcp` line just below `gem "ruby_llm"`.

- [ ] **Step 2: Install**

Run from project root:

```bash
bundle install
```

Expected: `fast-mcp (1.5.x)` printed in `Bundle complete!` block. If the resolver complains about Rails 8.1 incompatibility, pin to the highest available 1.x version that supports Rails 8 (`bundle outdated fast-mcp` will report).

- [ ] **Step 3: Verify it loads**

```bash
bundle exec rails runner 'puts FastMcp::VERSION'
```

Expected: prints a version string like `1.5.0`. If `NameError`, the gem didn't load — re-check `Gemfile` indentation (it must not be inside a `group :test` block).

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add fast-mcp gem for MCP server chassis"
```

---

## Task 2: Add `app/mcp` to autoload paths

**Files:**
- Modify: `/Users/bruno/Projects/rails/lewsnetter/config/application.rb`

- [ ] **Step 1: Open `config/application.rb`** and locate the `class Application < Rails::Application` block. Look for any existing `config.autoload_paths` lines.

- [ ] **Step 2: Add the autoload path**

Inside the class body (after any existing `config.autoload_paths +=` lines, or right after `config.eager_load_paths += ...` lines if those exist; otherwise at the top of the class body):

```ruby
# MCP server tools and middleware live under app/mcp. Zeitwerk needs the
# directory in autoload_paths to resolve `Mcp::Tool::Base`, etc.
config.autoload_paths += %W[#{config.root}/app/mcp]
config.eager_load_paths += %W[#{config.root}/app/mcp]
```

- [ ] **Step 3: Make the directory exist (otherwise Rails will warn)**

```bash
mkdir -p app/mcp/tool app/mcp/tools/team
```

- [ ] **Step 4: Verify boot is clean**

```bash
bundle exec rails runner 'puts "boot ok"'
```

Expected: prints `boot ok`. If you see "warning: empty autoload directory," that means a subdir has no `.rb` yet — that's fine; subsequent tasks add files. If Zeitwerk raises, the path is wrong.

- [ ] **Step 5: Commit**

```bash
git add config/application.rb
git commit -m "chore: autoload app/mcp for MCP server modules"
```

---

## Task 3: `Mcp::Tool::Context` value object

A small struct passed to every tool. Defining it first means the base class and tests below can reference it.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/app/mcp/tool/context.rb`
- Create: `/Users/bruno/Projects/rails/lewsnetter/test/mcp/tool/context_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/tool/context_test.rb
require "test_helper"

module Mcp
  module Tool
    class ContextTest < ActiveSupport::TestCase
      test "stores user and team and is frozen" do
        user = create(:onboarded_user)
        team = user.current_team
        ctx = Context.new(user: user, team: team)

        assert_equal user, ctx.user
        assert_equal team, ctx.team
        assert_predicate ctx, :frozen?
      end

      test "raises if user or team is nil" do
        assert_raises(ArgumentError) { Context.new(user: nil, team: create(:team)) }
        assert_raises(ArgumentError) { Context.new(user: create(:onboarded_user), team: nil) }
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bin/rails test test/mcp/tool/context_test.rb
```

Expected: FAIL with `NameError: uninitialized constant Mcp::Tool::Context`.

- [ ] **Step 3: Implement `Mcp::Tool::Context`**

```ruby
# app/mcp/tool/context.rb
# frozen_string_literal: true

module Mcp
  module Tool
    # Per-request context handed to every Mcp::Tool::Base subclass. Carries
    # the authenticated user + their current team (the token's resource
    # owner). Frozen so tools can't mutate it mid-call.
    class Context
      attr_reader :user, :team

      def initialize(user:, team:)
        raise ArgumentError, "user is required" if user.nil?
        raise ArgumentError, "team is required" if team.nil?
        @user = user
        @team = team
        freeze
      end
    end
  end
end
```

- [ ] **Step 4: Run the test, expect green**

```bash
bin/rails test test/mcp/tool/context_test.rb
```

Expected: 2 runs, 2 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/mcp/tool/context.rb test/mcp/tool/context_test.rb
git commit -m "feat(mcp): Mcp::Tool::Context value object for per-request state"
```

---

## Task 4: `Mcp::Tool::Base` abstract class

The contract every tool implements. Subclasses declare `tool_name`, `description`, `arguments_schema`, and a `#call(arguments:, context:)` method.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/app/mcp/tool/base.rb`
- Create: `/Users/bruno/Projects/rails/lewsnetter/test/mcp/tool/base_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/tool/base_test.rb
require "test_helper"

module Mcp
  module Tool
    class BaseTest < ActiveSupport::TestCase
      class FakeTool < Base
        tool_name "fake.do_something"
        description "Test tool"
        arguments_schema(
          type: "object",
          properties: {x: {type: "integer"}},
          required: ["x"]
        )

        def call(arguments:, context:)
          {received: arguments["x"], team_id: context.team.id}
        end
      end

      setup do
        @user = create(:onboarded_user)
        @team = @user.current_team
        @ctx = Context.new(user: @user, team: @team)
      end

      test "subclass exposes tool_name, description, arguments_schema" do
        assert_equal "fake.do_something", FakeTool.tool_name
        assert_equal "Test tool", FakeTool.description
        assert_equal "object", FakeTool.arguments_schema[:type]
      end

      test "#invoke validates arguments against schema and calls" do
        result = FakeTool.new.invoke(arguments: {"x" => 7}, context: @ctx)
        assert_equal({received: 7, team_id: @team.id}, result)
      end

      test "#invoke raises Mcp::Tool::ArgumentError when required field missing" do
        assert_raises(Mcp::Tool::ArgumentError) do
          FakeTool.new.invoke(arguments: {}, context: @ctx)
        end
      end

      test "base #call raises NotImplementedError" do
        assert_raises(NotImplementedError) do
          Base.new.call(arguments: {}, context: @ctx)
        end
      end

      test "Base.descendants accumulates registered subclasses" do
        assert_includes Base.descendants, FakeTool
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL**

```bash
bin/rails test test/mcp/tool/base_test.rb
```

Expected: FAIL with `NameError: uninitialized constant Mcp::Tool::Base`.

- [ ] **Step 3: Implement `Mcp::Tool::Base`**

```ruby
# app/mcp/tool/base.rb
# frozen_string_literal: true

require "json-schema"

module Mcp
  module Tool
    class ArgumentError < StandardError; end

    # Abstract base class for MCP tools. Subclasses declare metadata via the
    # DSL (`tool_name`, `description`, `arguments_schema`) and implement
    # `#call(arguments:, context:)`. The loader at boot enumerates
    # `Base.descendants` and registers each with the FastMcp server.
    class Base
      class << self
        attr_reader :_tool_name, :_description, :_arguments_schema

        def tool_name(name = nil)
          return @_tool_name if name.nil?
          @_tool_name = name
        end

        def description(text = nil)
          return @_description if text.nil?
          @_description = text
        end

        def arguments_schema(schema = nil)
          return @_arguments_schema if schema.nil?
          @_arguments_schema = schema
        end

        # Tracks every subclass so the loader doesn't have to walk the
        # filesystem twice.
        def descendants
          @descendants ||= []
        end

        def inherited(subclass)
          super
          Base.descendants << subclass
        end
      end

      def call(arguments:, context:)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # Validates arguments, then dispatches to #call. The server invokes
      # this — never #call directly — so schema validation is centralized.
      def invoke(arguments:, context:)
        validate!(arguments)
        call(arguments: arguments, context: context)
      end

      private

      def validate!(arguments)
        schema = self.class.arguments_schema
        return if schema.nil?
        errors = JSON::Validator.fully_validate(schema, arguments)
        return if errors.empty?
        raise ArgumentError, errors.join("; ")
      end
    end
  end
end
```

- [ ] **Step 4: Add `json-schema` to the Gemfile** (already a transitive dep of many gems but pin it explicitly so the require above never breaks)

In `Gemfile`, near the `fast-mcp` line you added in Task 1, add:

```ruby
# JSON Schema validation for MCP tool argument schemas.
gem "json-schema", "~> 5.1"
```

Then:

```bash
bundle install
```

Expected: `json-schema (5.x.x)` shown in install output.

- [ ] **Step 5: Run the tests, expect green**

```bash
bin/rails test test/mcp/tool/base_test.rb
```

Expected: 5 runs, 7 assertions, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/mcp/tool/base.rb test/mcp/tool/base_test.rb Gemfile Gemfile.lock
git commit -m "feat(mcp): Mcp::Tool::Base with schema validation + descendant tracking"
```

---

## Task 5: First tool — `Mcp::Tools::Team::GetCurrent`

A trivial tool that returns the calling team's id, name, and slug. Proves the pattern; future tools follow this shape.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/app/mcp/tools/team/get_current.rb`
- Create: `/Users/bruno/Projects/rails/lewsnetter/test/mcp/tools/team/get_current_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/tools/team/get_current_test.rb
require "test_helper"

module Mcp
  module Tools
    module Team
      class GetCurrentTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
        end

        test "returns id, name, and slug for the context's team" do
          result = GetCurrent.new.invoke(arguments: {}, context: @ctx)
          assert_equal @team.id, result[:id]
          assert_equal @team.name, result[:name]
          assert_equal @team.slug, result[:slug]
        end

        test "metadata is wired" do
          assert_equal "team.get_current", GetCurrent.tool_name
          assert_match(/team/i, GetCurrent.description)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL**

```bash
bin/rails test test/mcp/tools/team/get_current_test.rb
```

Expected: `NameError: uninitialized constant Mcp::Tools::Team::GetCurrent`.

- [ ] **Step 3: Implement the tool**

```ruby
# app/mcp/tools/team/get_current.rb
# frozen_string_literal: true

module Mcp
  module Tools
    module Team
      class GetCurrent < Mcp::Tool::Base
        tool_name "team.get_current"
        description "Returns the id, name, and slug of the team that owns the calling token."
        arguments_schema(type: "object", properties: {}, additionalProperties: false)

        def call(arguments:, context:)
          team = context.team
          {id: team.id, name: team.name, slug: team.slug}
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect green**

```bash
bin/rails test test/mcp/tools/team/get_current_test.rb
```

Expected: 2 runs, 4 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/mcp/tools/team/get_current.rb test/mcp/tools/team/get_current_test.rb
git commit -m "feat(mcp): team.get_current — first MCP tool, proves the pattern"
```

---

## Task 6: `Mcp::Tool::Loader`

Enumerates `app/mcp/tools/**/*.rb` (forces autoload of all tool files), then returns `Mcp::Tool::Base.descendants`. Used by both the server and the in-process agent (Phase 5) to discover tools.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/app/mcp/tool/loader.rb`
- Create: `/Users/bruno/Projects/rails/lewsnetter/test/mcp/tool/loader_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/tool/loader_test.rb
require "test_helper"

module Mcp
  module Tool
    class LoaderTest < ActiveSupport::TestCase
      test "discovers all tool files and returns Base descendants" do
        tools = Loader.load_all
        assert tools.is_a?(Array)
        assert tools.all? { |klass| klass < Mcp::Tool::Base }
        names = tools.map(&:tool_name)
        assert_includes names, "team.get_current"
      end

      test "tool names are unique" do
        names = Loader.load_all.map(&:tool_name)
        duplicates = names.tally.select { |_, count| count > 1 }.keys
        assert_empty duplicates, "Duplicate tool_name(s): #{duplicates.inspect}"
      end
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** (`uninitialized constant Mcp::Tool::Loader`)

```bash
bin/rails test test/mcp/tool/loader_test.rb
```

- [ ] **Step 3: Implement the loader**

```ruby
# app/mcp/tool/loader.rb
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
          # Translate "app/mcp/tools/team/get_current.rb" to the constant.
          require_dependency path
        end
        Mcp::Tool::Base.descendants.sort_by(&:tool_name)
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect green**

```bash
bin/rails test test/mcp/tool/loader_test.rb
```

Expected: 2 runs, 4 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/mcp/tool/loader.rb test/mcp/tool/loader_test.rb
git commit -m "feat(mcp): Mcp::Tool::Loader enumerates tools at boot"
```

---

## Task 7: `Mcp::DoorkeeperAuth` Rack middleware

Validates `Authorization: Bearer <token>` against `Doorkeeper::AccessToken` (Lewsnetter's `Platform::AccessToken`). On success, sets `env["mcp.user"]` and `env["mcp.team"]`. On failure, returns a JSON-RPC `401` error.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/app/mcp/doorkeeper_auth.rb`
- Create: `/Users/bruno/Projects/rails/lewsnetter/test/mcp/doorkeeper_auth_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/mcp/doorkeeper_auth_test.rb
require "test_helper"

module Mcp
  class DoorkeeperAuthTest < ActiveSupport::TestCase
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @app = create(:platform_application, team: @team)
      @token = Doorkeeper::AccessToken.create!(
        resource_owner_id: @user.id,
        application: @app,
        scopes: "read write delete",
        token: SecureRandom.hex
      )
      @inner = ->(env) { [200, {"content-type" => "application/json"}, [{ok: true, user_id: env["mcp.user"]&.id, team_id: env["mcp.team"]&.id}.to_json]] }
      @middleware = DoorkeeperAuth.new(@inner)
    end

    test "passes through with valid Bearer token" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{@token.token}", method: "POST")
      status, _headers, body = @middleware.call(env)
      assert_equal 200, status
      payload = JSON.parse(body.first)
      assert_equal @user.id, payload["user_id"]
      assert_equal @team.id, payload["team_id"]
    end

    test "returns 401 JSON-RPC error when no Authorization header" do
      env = Rack::MockRequest.env_for("/mcp", method: "POST")
      status, headers, body = @middleware.call(env)
      assert_equal 401, status
      assert_equal "application/json", headers["content-type"]
      payload = JSON.parse(body.first)
      assert_equal(-32001, payload["error"]["code"])
      assert_match(/missing bearer token/i, payload["error"]["message"])
    end

    test "returns 401 when token is unknown" do
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer not-a-real-token", method: "POST")
      status, _headers, body = @middleware.call(env)
      assert_equal 401, status
      payload = JSON.parse(body.first)
      assert_match(/invalid token/i, payload["error"]["message"])
    end

    test "returns 401 when token is revoked" do
      @token.revoke
      env = Rack::MockRequest.env_for("/mcp", "HTTP_AUTHORIZATION" => "Bearer #{@token.token}", method: "POST")
      status, _headers, _body = @middleware.call(env)
      assert_equal 401, status
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** (`uninitialized constant Mcp::DoorkeeperAuth`)

```bash
bin/rails test test/mcp/doorkeeper_auth_test.rb
```

- [ ] **Step 3: Implement the middleware**

```ruby
# app/mcp/doorkeeper_auth.rb
# frozen_string_literal: true

module Mcp
  # Rack middleware that validates `Authorization: Bearer <token>` against
  # Doorkeeper::AccessToken (Lewsnetter's Platform::AccessToken). On success
  # it places the resolved user + their current team in the Rack env so the
  # MCP server can build an Mcp::Tool::Context. On failure it returns a
  # JSON-RPC 401 with code -32001 (server-defined "invalid token").
  class DoorkeeperAuth
    JSONRPC_INVALID_TOKEN = -32001

    def initialize(app)
      @app = app
    end

    def call(env)
      header = env["HTTP_AUTHORIZATION"]
      return error(401, "Missing Bearer token") if header.blank?

      match = header.match(/\ABearer\s+(.+)\z/)
      return error(401, "Invalid Authorization header") unless match

      token = Doorkeeper::AccessToken.by_token(match[1])
      return error(401, "Invalid token") unless token&.acceptable?(nil)

      user = User.find_by(id: token.resource_owner_id)
      return error(401, "Token resource owner not found") if user.nil?

      team = user.current_team
      return error(401, "Token resource owner has no current team") if team.nil?

      env["mcp.user"] = user
      env["mcp.team"] = team
      @app.call(env)
    end

    private

    def error(status, message)
      body = {
        jsonrpc: "2.0",
        error: {code: JSONRPC_INVALID_TOKEN, message: message},
        id: nil
      }.to_json
      [status, {"content-type" => "application/json"}, [body]]
    end
  end
end
```

- [ ] **Step 4: Run, expect green**

```bash
bin/rails test test/mcp/doorkeeper_auth_test.rb
```

Expected: 4 runs, 11 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/mcp/doorkeeper_auth.rb test/mcp/doorkeeper_auth_test.rb
git commit -m "feat(mcp): Mcp::DoorkeeperAuth Rack middleware"
```

---

## Task 8: `Mcp::Server` — wires tools into a `FastMcp::Server`

Builds the server instance and exposes a `.rack_app` Rack-callable that handles the MCP JSON-RPC protocol. Per-request, it pulls `mcp.user` / `mcp.team` from the env and passes a `Context` to each tool invocation.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/app/mcp/server.rb`

> **Note on `fast-mcp` API:** the `fast-mcp` gem version pinned in Task 1 (`~> 1.5`) registers tools via `server.register_tool(name:, description:, input_schema:, &handler)`. If your installed version uses a different signature, run `bundle exec ri FastMcp::Server` and adapt the call site below; the contract — name + description + JSON Schema + a callable that receives parsed params — is stable across versions.

- [ ] **Step 1: Write the file**

```ruby
# app/mcp/server.rb
# frozen_string_literal: true

require "fast_mcp"

module Mcp
  # Builds a singleton FastMcp::Server with all Mcp::Tool::Base descendants
  # registered. `rack_app` returns a Rack-callable mounted at /mcp by
  # config/routes.rb. Per-request, the user + team set by DoorkeeperAuth
  # are read from the env and packaged into an Mcp::Tool::Context that's
  # handed to each tool invocation.
  module Server
    module_function

    def instance
      @instance ||= build
    end

    def rack_app
      app = instance.rack_app
      lambda do |env|
        # Stash the per-request context where the tool handlers can read it.
        Thread.current[:mcp_context] = Mcp::Tool::Context.new(
          user: env.fetch("mcp.user"),
          team: env.fetch("mcp.team")
        )
        app.call(env)
      ensure
        Thread.current[:mcp_context] = nil
      end
    end

    def build
      server = FastMcp::Server.new(name: "lewsnetter", version: Lewsnetter::VERSION || "0.0.0")
      Mcp::Tool::Loader.load_all.each do |tool_class|
        register(server, tool_class)
      end
      server
    end

    def register(server, tool_class)
      handler = lambda do |params|
        ctx = Thread.current[:mcp_context]
        raise "missing per-request MCP context" if ctx.nil?
        tool_class.new.invoke(arguments: params || {}, context: ctx)
      end

      server.register_tool(
        name: tool_class.tool_name,
        description: tool_class.description,
        input_schema: tool_class.arguments_schema || {type: "object", properties: {}},
        &handler
      )
    end
  end
end
```

> **About `Lewsnetter::VERSION`:** if no such constant exists in the app, replace with the literal string `"0.1.0"`. Don't add a VERSION constant just for this.

- [ ] **Step 2: Verify boot is still clean**

```bash
bundle exec rails runner 'Mcp::Server.instance; puts "ok"'
```

Expected: prints `ok`. If it raises about `Lewsnetter::VERSION` undefined, replace that reference with `"0.1.0"` per the note above and retry.

- [ ] **Step 3: Commit**

```bash
git add app/mcp/server.rb
git commit -m "feat(mcp): Mcp::Server wires tools into FastMcp::Server"
```

---

## Task 9: Mount `/mcp` in routes

**Files:**
- Modify: `/Users/bruno/Projects/rails/lewsnetter/config/routes.rb`

- [ ] **Step 1: Find the mount point**

Open `config/routes.rb`. Find the block where `/unsubscribe/:token` is defined (it's BEFORE the BulletTrain engines). The MCP mount goes in the same area — before any session-authenticated routes — so the request never touches Devise / CSRF.

- [ ] **Step 2: Add the route**

Right after the `post "/webhooks/ses/sns"` line, before the BulletTrain engines `draw "concerns"`, add:

```ruby
# MCP server. Token-authed via Mcp::DoorkeeperAuth middleware (mounted
# inline below). Mounted BEFORE the BulletTrain engines so it skips
# Devise/CSRF and runs as a pure Rack endpoint.
mount Rack::Builder.new {
  use Mcp::DoorkeeperAuth
  run ->(env) { Mcp::Server.rack_app.call(env) }
} => "/mcp"
```

- [ ] **Step 3: Confirm the route is registered**

```bash
bin/rails routes | grep mcp
```

Expected output includes:

```
                                /mcp        Rack::Builder
```

- [ ] **Step 4: Sanity-curl the endpoint with no auth (server should be running)**

In one terminal:

```bash
bin/dev
```

In another:

```bash
curl -s -X POST http://localhost:3000/mcp -H 'content-type: application/json' -d '{}' | jq .
```

Expected:

```json
{
  "jsonrpc": "2.0",
  "error": {"code": -32001, "message": "Missing Bearer token"},
  "id": null
}
```

If you get the Devise sign-in page HTML instead, the mount happened AFTER the BulletTrain engines — move it earlier.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb
git commit -m "feat(mcp): mount /mcp Rack endpoint with Doorkeeper auth"
```

---

## Task 10: End-to-end integration test

The big one. Boots the app, hits `/mcp` with a real token, runs an `initialize` handshake + `tools/list` + `tools/call team.get_current`, and asserts each step.

**Files:**
- Create: `/Users/bruno/Projects/rails/lewsnetter/test/mcp/server_integration_test.rb`

- [ ] **Step 1: Write the failing integration test**

```ruby
# test/mcp/server_integration_test.rb
require "test_helper"

module Mcp
  class ServerIntegrationTest < ActionDispatch::IntegrationTest
    setup do
      @user = create(:onboarded_user)
      @team = @user.current_team
      @platform_application = create(:platform_application, team: @team)
      @token = Doorkeeper::AccessToken.create!(
        resource_owner_id: @user.id,
        application: @platform_application,
        scopes: "read write delete",
        token: SecureRandom.hex
      )
    end

    def post_mcp(body)
      post "/mcp",
        params: body.to_json,
        headers: {
          "Authorization" => "Bearer #{@token.token}",
          "Content-Type" => "application/json"
        }
    end

    test "401 without auth" do
      post "/mcp", params: "{}", headers: {"Content-Type" => "application/json"}
      assert_response :unauthorized
      payload = JSON.parse(response.body)
      assert_equal(-32001, payload["error"]["code"])
    end

    test "initialize handshake returns server info" do
      post_mcp(jsonrpc: "2.0", id: 1, method: "initialize", params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: {name: "test", version: "0.0.1"}
      })
      assert_response :success
      payload = JSON.parse(response.body)
      assert_equal "2.0", payload["jsonrpc"]
      assert_equal 1, payload["id"]
      assert_equal "lewsnetter", payload.dig("result", "serverInfo", "name")
    end

    test "tools/list includes team.get_current" do
      post_mcp(jsonrpc: "2.0", id: 2, method: "tools/list")
      assert_response :success
      payload = JSON.parse(response.body)
      names = payload.dig("result", "tools").map { |t| t["name"] }
      assert_includes names, "team.get_current"
    end

    test "tools/call team.get_current returns the calling team" do
      post_mcp(jsonrpc: "2.0", id: 3, method: "tools/call", params: {
        name: "team.get_current",
        arguments: {}
      })
      assert_response :success
      payload = JSON.parse(response.body)
      content = payload.dig("result", "content")
      refute_nil content, "Expected result.content in #{payload.inspect}"
      # FastMcp wraps the tool's return as a content array. The tool
      # returned a hash; assert the team id appears somewhere in the
      # serialized content.
      assert_includes content.to_json, %("id":#{@team.id})
      assert_includes content.to_json, @team.name
    end
  end
end
```

- [ ] **Step 2: Run, expect FAIL** (the server isn't booted into the test app yet — likely route-not-found)

```bash
bin/rails test test/mcp/server_integration_test.rb
```

Expected: failures complaining about route or response shape.

- [ ] **Step 3: If failures are about response shape (FastMcp returning a slightly different envelope), adjust the assertions to match**

The response shape from `fast-mcp` for `tools/call` is documented in its README. The test above assumes the standard MCP shape: `{jsonrpc, id, result: {content: [...]}}`. If the gem returns `result.toolResult` or wraps content differently, update the test's content assertion accordingly. Do NOT loosen the auth or routing assertions — those should pass as written.

- [ ] **Step 4: If failures are about routing**

Re-check Task 9. Common cause: `mount` placed inside a `namespace` block. It should be at the top level of `routes.rb`, near `/unsubscribe/:token`.

- [ ] **Step 5: When all four tests are green**

```bash
bin/rails test test/mcp/server_integration_test.rb
```

Expected: 4 runs, ≥10 assertions, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/mcp/server_integration_test.rb
git commit -m "test(mcp): end-to-end integration coverage for /mcp endpoint"
```

---

## Task 11: Run the full suite

Make sure nothing existing broke (CSRF / session-auth paths, existing API tests, AI service tests).

- [ ] **Step 1: Run everything**

```bash
bin/rails test
```

Expected: any pre-existing failures (the SESSION-HANDOFF flagged BulletTrain scaffold tests + factory gaps) remain, but no NEW failures attributable to MCP changes. If a previously-passing test now fails, debug before merging — likely autoload ordering or a route collision.

- [ ] **Step 2: If clean, no commit needed.** If you had to fix something downstream:

```bash
git add -p
git commit -m "fix: <what you fixed>"
```

---

## Task 12: Manual smoke

End-to-end with a real token, real server.

- [ ] **Step 1: Start the dev server**

```bash
bin/dev
```

- [ ] **Step 2: Mint a token in the rails console**

In another terminal:

```bash
bin/rails runner '
  user = User.find_by!(email: "qa@local.test")
  team = user.current_team
  app = Platform::Application.find_or_create_by!(name: "MCP smoke", team: team) do |a|
    a.user = user
    a.uid = SecureRandom.hex(8)
    a.secret = SecureRandom.hex(16)
    a.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
  end
  token = Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: app, scopes: "read write delete", token: SecureRandom.hex)
  puts token.token
'
```

Copy the printed token.

- [ ] **Step 3: Hit the endpoint**

```bash
TOKEN=<paste-token>
curl -s -X POST http://localhost:3000/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"team.get_current","arguments":{}}}' | jq .
```

Expected: a JSON-RPC response carrying the team's id, name, and slug.

- [ ] **Step 4: If green, you're done with Phase 1.**

Push when ready:

```bash
git push origin master
```

(Or if the repo's flow prefers a branch + PR, branch off this commit set with `git switch -c feature/mcp-chassis` before the push.)

---

## Self-review

**Spec coverage:**
- [x] Spec §"MCP server" → Tasks 1–10 (gem, mount, auth, registry).
- [x] Spec §"Authorization" via Doorkeeper → Task 7 + Task 10's auth assertion.
- [x] Spec §"Tool registry" file layout (`app/mcp/tools/<group>/<verb>.rb`) → Tasks 4–6 establish the pattern via `team.get_current`.
- [x] Spec §"Failure / degradation matrix" first row (token invalid → 401) → Task 7 + Task 10.
- [x] Phase 1 boundary as defined in the spec ("Chassis: gem + mount + middleware + Base + loader + one trivial tool wired E2E with passing test") → exactly Tasks 1–11.

Not in this plan (deferred to subsequent phase plans, intentional):
- Raw API tools surface (Phase 2).
- `Mcp::Skill::Loader` + skill resources (Phase 3).
- `Llm::Configuration` + `llm.*` tools (Phase 4).
- Telemetry hooks (`Rails.logger.tagged("mcp")`) — should be added in Phase 2 alongside the per-tool wrapper.

**Type / name consistency:**
- `Mcp::Tool::Base`, `Mcp::Tool::Context`, `Mcp::Tool::Loader`, `Mcp::DoorkeeperAuth`, `Mcp::Server`, `Mcp::Tools::Team::GetCurrent` — checked across all tasks. Module nesting matches paths.
- `arguments_schema` used everywhere; not `arguments`, not `input_schema` (in tool subclasses; `input_schema` is only used at the FastMcp registration boundary in Task 8).
- `tool_name` is the DSL method on the class; the actual public attribute is also called `tool_name` (returned by the same getter).

**Placeholders:** none.

**Ambiguity resolved inline:**
- `Lewsnetter::VERSION` reference in Task 8 has a fallback note.
- The `fast-mcp` registration API note in Task 8 acknowledges the contract may vary by version.
- Test assertion shape in Task 10 has explicit "if it doesn't match, adjust the test" guidance because the JSON-RPC content envelope is the most likely incompatibility surface.
