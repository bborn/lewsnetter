# Cross-Link Existing AI Panels to the Agent (Phase 6 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Each existing AI panel (campaign drafter, segment translator, post-send analyst) grows a small "Open in agent" affordance that pre-fills a starter prompt, kicking off a new conversation. Telemetry-light way to see whether users prefer the agent path. Bespoke panels keep working.

**Architecture:** `AgentConversationsController#create` accepts an optional `starter_prompt` param, persists it as the first user message, fires `Agent::Runner` synchronously (or in a job), then redirects to the show page where the Cable-backed UI takes over.

**Tech Stack:** Same as Phase 5 — no new gems.

**Reference spec:** `docs/superpowers/specs/2026-05-15-mcp-and-in-app-agent-design.md` §"Replacing existing panels"

---

## Task 1: `AgentConversationsController#create` accepts starter_prompt

**Files:**
- Modify: `app/controllers/account/agent_conversations_controller.rb`
- Modify: existing test if any

- [ ] **Step 1:** Update the `create` action:

```ruby
def create
  @agent_conversation.user = current_user
  if @agent_conversation.save
    starter = params[:starter_prompt].to_s.strip
    if starter.present?
      Agent::Runner.new(conversation: @agent_conversation).handle_user_message(starter)
    end
    redirect_to [:account, @agent_conversation]
  else
    redirect_to [:account, current_team, :agent_conversations], alert: "Could not start conversation"
  end
end
```

- [ ] **Step 2: Test**

```ruby
# test/controllers/account/agent_conversations_controller_test.rb (or add to existing)
require "test_helper"

class Account::AgentConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:onboarded_user)
    @team = @user.current_team
    sign_in @user
    AI::Base.force_stub = true
  end

  teardown { AI::Base.force_stub = false }

  test "create with starter_prompt persists the prompt as a user message and runs the agent" do
    assert_difference -> { AgentConversation.count }, 1 do
      post account_team_agent_conversations_path(@team), params: {agent_conversation: {}, starter_prompt: "Draft a newsletter for me."}
    end
    conv = AgentConversation.last
    assert_equal @user.id, conv.user_id
    assert_equal @team.id, conv.team_id
    assert conv.agent_messages.where(role: "user").exists?(content: "Draft a newsletter for me.")
    assert conv.agent_messages.where(role: "assistant").exists?  # stub reply, but present
    assert_redirected_to [:account, conv]
  end

  test "create without starter_prompt just creates an empty conversation" do
    post account_team_agent_conversations_path(@team), params: {agent_conversation: {}}
    conv = AgentConversation.last
    assert_equal 0, conv.agent_messages.count
  end
end
```

If `sign_in` from Devise's test helpers isn't available in `ActionDispatch::IntegrationTest`, look at how an existing controller test signs in (e.g. `test/controllers/account/campaigns_controller_test.rb`). Common pattern: `post user_session_path, params: {user: {email: @user.email, password: "password"}}` first, OR include `Devise::Test::IntegrationHelpers` at the top of the test class.

- [ ] **Step 3:** Run, expect green.

- [ ] **Step 4:** Commit:

```bash
git add app/controllers/account/agent_conversations_controller.rb test/controllers/account/agent_conversations_controller_test.rb
git commit -m "feat(agent): accept starter_prompt param to seed a new conversation"
```

---

## Task 2: Helper for "Open in agent" links

A small ApplicationHelper method for consistency.

**Files:**
- Modify: `app/helpers/application_helper.rb` (or create `app/helpers/agent_helper.rb`)

- [ ] **Step 1:** Add to `app/helpers/application_helper.rb` (or a new helper file if you prefer):

```ruby
# In ApplicationHelper or AgentHelper

# Renders an "Open in agent" link that creates a new AgentConversation
# pre-seeded with the given prompt. Example:
#   <%= open_in_agent_link("Draft a newsletter about: #{@brief}", label: "→ Open in agent") %>
def open_in_agent_link(prompt, label: "→ Open in agent", html_options: {})
  return unless user_signed_in? && current_team
  button_to(
    label,
    account_team_agent_conversations_path(current_team),
    method: :post,
    params: {agent_conversation: {}, starter_prompt: prompt},
    class: html_options[:class] || "card-action",
    data: html_options[:data] || {turbo: false}
  )
end
```

The `data-turbo: false` ensures a full-page navigation on submit (we want to land on the conversation show page, not Turbo-replace the current page). Adjust the class to match the surrounding context — `.card-action` is the existing mono-caps eyebrow link style.

- [ ] **Step 2: Commit**

```bash
git add app/helpers/application_helper.rb
git commit -m "feat(agent): open_in_agent_link helper"
```

---

## Task 3: Wire the cross-links into existing AI panels

Three places to update. Each gets one line added near the existing AI panel UI.

### 3a: Campaign drafter (campaign edit form)

Find the AI drafter section in `app/views/account/campaigns/_form.html.erb` (or wherever the orange-tinted "Draft with AI" panel lives — search for `data-controller="ai-drafter"`).

Add the link in the panel header or footer:

```erb
<% if @campaign && @campaign.persisted? %>
  <%= open_in_agent_link(
    "Draft a campaign for the team. Existing campaign id #{@campaign.id} subject is \"#{@campaign.subject}\". Pick a segment if none is set, refine the body, and prepare to send.",
    label: "→ OPEN IN AGENT INSTEAD"
  ) %>
<% end %>
```

### 3b: Segment translator (segment new/edit form)

Find the segment translator panel — likely in `app/views/account/segments/_form.html.erb` or a partial included from there.

Add:

```erb
<%= open_in_agent_link(
  "Help me build a segment for #{current_team.name}. Show me the team's custom_attribute schema, then ask what audience I want to target.",
  label: "→ OPEN IN AGENT INSTEAD"
) %>
```

### 3c: Post-send analyst (campaign show page)

Find the "Analyze with AI" button on `app/views/account/campaigns/show.html.erb` — search for postmortem-related code.

Add:

```erb
<% if @campaign.status == "sent" %>
  <%= open_in_agent_link(
    "Analyze the recent send: campaign id #{@campaign.id}, subject \"#{@campaign.subject}\". Pull stats, identify what worked, and suggest 3 actions.",
    label: "→ OPEN IN AGENT INSTEAD"
  ) %>
<% end %>
```

- [ ] **Step 1:** Find each AI panel by grepping for `ai-drafter`, `segment-translator`, and `campaign_postmortems` references.
- [ ] **Step 2:** Add the link in each. Style consistently — use `.card-action` (mono caps small) so it reads as a quiet alternative, not a CTA competing with the bespoke panel's primary action.
- [ ] **Step 3:** Visual smoke: boot dev, navigate to a campaign edit page, segment form, and a sent campaign's show page. Confirm the link renders, click it, confirm you land on the agent's show page with the pre-seeded message.
- [ ] **Step 4:** Commit:

```bash
git add app/views/account/campaigns/ app/views/account/segments/
git commit -m "feat(agent): cross-link existing AI panels to Open in agent"
```

---

## Task 4: Final smoke + suite

- [ ] **Step 1:** `bin/rails test` — confirm no regressions (pre-existing failures unchanged).

- [ ] **Step 2:** Update SESSION-HANDOFF or CHANGELOG.md briefly noting the new MCP feature is live.

- [ ] **Step 3:** Push to origin:

```bash
git push -u origin feature/mcp-chassis
```

- [ ] **Step 4:** Open a PR (manual or via `gh pr create`).

---

## Self-review

**Spec coverage:**
- [x] Spec §"Replacing existing panels" — Tasks 1-3 add the cross-link affordance. Bespoke panels keep working (we didn't remove anything).
- [x] Phase 6 boundary as defined: small, only cross-linking. Removal of bespoke panels is a future decision gated on telemetry.

**Type / name consistency:** `open_in_agent_link` helper is the single entry point; all three call sites use it.

**Placeholders:** none.

**Implementation deviations expected:**
- The exact partial paths for the three AI panels may differ from what the plan guesses; greps in Task 3 step 1 surface the truth.
- If `Devise::Test::IntegrationHelpers` isn't already included, add it at the top of the controller test file: `include Devise::Test::IntegrationHelpers`.
