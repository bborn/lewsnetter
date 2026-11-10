require "test_helper"

# The Intercom Series port, end to end on a real exported series (two of
# "Connect Accts (Never Connected)"'s emails, trimmed to their content):
# blocks → markdown, the importer's sequence/step/segment wiring, and the
# rendered email with Intercom's merge tags resolved.
class Sequences::IntercomSeriesImportTest < ActiveSupport::TestCase
  EXPORT_DIR = Rails.root.join("test/fixtures/files/intercom_series")
  EMAIL_1 = "43856798" # button with {{custom_data.subdomain|fallback:"www"}}
  EMAIL_4 = "43879339" # URL-encoded tag inside an <a href>, plus an A/B variant

  setup do
    @team = create(:team)
    @sender = @team.sender_addresses.create!(
      email: "hello@example.com", name: "Hello", verified: true, ses_status: "verified"
    )
    @template = @team.email_templates.create!(name: "Ported",
      mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>{{body}}</mj-text></mj-column></mj-section></mj-body></mjml>")
    @export = JSON.parse(EXPORT_DIR.join("381681.json").read)
  end

  test "blocks convert to markdown with merge tags intact" do
    md, warnings = Sequences::IntercomBlocks.to_markdown(blocks(EMAIL_1))
    assert_empty warnings
    assert_includes md, %(Hi {{first_name|fallback:"there"}}!)
    assert_includes md, %(**[Connect my accounts](https://{{custom_data.subdomain|fallback:"www"}}.influencekit.com/tokens)**)
    assert_includes md, "Chris  \nCo-founder | InfluenceKit"

    md4, = Sequences::IntercomBlocks.to_markdown(blocks(EMAIL_4))
    assert_includes md4, %{(https://{{custom_data.subdomain | fallback:"www"}}.influencekit.com/tokens)}
    assert_includes md4, "haven't connected", "HTML entities decode"
  end

  test "a paragraph starting with a number or # stays a paragraph" do
    md, = Sequences::IntercomBlocks.to_markdown([
      {"type" => "paragraph", "text" => "#1 tip"}, {"type" => "paragraph", "text" => "2. step"}
    ])
    assert_equal "\\#1 tip\n\n\\2. step", md
  end

  test "real exported bodies render every link with the subscriber's subdomain, or the fallback" do
    [EMAIL_1, EMAIL_4].each do |ruleset|
      md, = Sequences::IntercomBlocks.to_markdown(blocks(ruleset))
      campaign = @team.campaigns.create!(email_template: @template, sender_address: @sender,
        subject: "x", body_markdown: md, status: "draft")

      with = @team.subscribers.create!(email: "a-#{ruleset}@example.com", name: "Sam Lee", subscribed: true,
        custom_attributes: {"subdomain" => "acme"})
      html = CampaignRenderer.new(campaign: campaign, subscriber: with).call.html
      assert_includes html, %(href="https://acme.influencekit.com/tokens"), "ruleset #{ruleset}"
      assert_includes html, "Hi Sam!"
      assert_no_match(/\{\{|%7B%7B|fallback/, html, "no merge tag left unrendered (#{ruleset})")

      without = @team.subscribers.create!(email: "b-#{ruleset}@example.com", subscribed: true)
      html = CampaignRenderer.new(campaign: campaign, subscriber: without).call.html
      assert_includes html, %(href="https://www.influencekit.com/tokens"), "ruleset #{ruleset}"
      assert_match(/Hi\s+there!/, html)
    end
  end

  test "imports a draft sequence with goal, step actions, finish wait and segments" do
    other = @team.sequences.create!(name: "Engagement", trigger_type: "event", trigger_event_name: "x")
    results = import(spec(exclude: ["Engagement", 999]))

    result = results.first
    assert_equal :created, result.status
    sequence = result.sequence
    assert sequence.draft?
    assert_equal "segment", sequence.trigger_type
    assert_equal "Never connected", sequence.trigger_segment.name
    assert_equal "Connected", sequence.exit_segment.name
    assert_equal "account:connected", sequence.goal_event_name
    assert_equal 3 * 1440, sequence.finish_after_minutes
    assert_equal "Didn't connect", sequence.completed_tag
    assert_equal [other.id], sequence.excluded_sequence_ids
    assert_equal @sender, sequence.sender_address

    first, second = sequence.steps
    assert_equal "[Action Needed] Connect Your Accounts💥", first.subject
    assert_equal 0, first.delay_minutes
    assert_equal ["goal", "Connected", true], [first.action_trigger, first.action_tag, first.action_exit]
    assert_equal @template, first.email_template
    assert_equal 8 * 1440 + 12 * 60, second.delay_minutes
    assert_equal "Connected", second.skip_segment.name
    assert_equal "Sent reminder", second.sent_tag
    assert_includes second.body_markdown, "connect your accounts"

    assert_includes result.warnings, "#{EMAIL_4}: A/B variant dropped (kept version A)"
    assert_includes result.warnings, "excluded series 999 isn't ported: rule dropped"
    assert_equal ["posts dropped"], result.changes

    assert_equal 2, @team.segments.where(name: ["Never connected", "Connected"]).count
    tagged = @team.subscribers.create!(email: "t@example.com", subscribed: true, tags: ["Connected"])
    assert sequence.subscriber_in_segment?(sequence.exit_segment, tagged)
  end

  test "re-running skips sequences that already exist" do
    import(spec)
    assert_no_difference -> { Sequence.count } do
      assert_equal :exists, import(spec).first.status
    end
  end

  test "a bad spec raises and creates nothing" do
    bad = spec
    bad["series"].first["steps"] << {"email" => "123"}
    assert_no_difference ["Sequence.count", "Segment.count"] do
      assert_raises(Sequences::IntercomSeriesImporter::SpecError) { import(bad) }
    end
  end

  private

  def blocks(ruleset)
    @export.dig("rulesets", ruleset, "ruleset_links", 0, "object", "localized_email_contents", 0, "blocks")
  end

  def import(spec)
    Sequences::IntercomSeriesImporter.new(team: @team, export_dir: EXPORT_DIR, spec: spec,
      sender_address: @sender, email_template: @template).call
  end

  def spec(exclude: [])
    {
      "segments" => {
        "Never connected" => {"predicate" => "COALESCE(json_extract(subscribers.custom_attributes, '$.tokens_count'), 0) = 0"},
        "Connected" => {"rules" => {"type" => "group", "combinator" => "and", "rules" => [
          {"type" => "rule", "field" => "subscribers.tags", "operator" => "contains", "value" => "Connected"}
        ]}}
      },
      "series" => [{
        "intercom_id" => 381681,
        "name" => "Connect accounts",
        "trigger" => {"segment" => "Never connected"},
        "exclude" => exclude,
        "goal" => {"event" => "account:connected"},
        "exit_segment" => "Connected",
        "finish_after_days" => 3,
        "completed_tag" => "Didn't connect",
        "steps" => [
          {"email" => EMAIL_1, "action" => {"on" => "goal", "tag" => "Connected", "exit" => true}},
          {"email" => EMAIL_4, "wait_days" => 8, "wait_hours" => 12, "skip_segment" => "Connected",
           "sent_tag" => "Sent reminder"}
        ],
        "changes" => ["posts dropped"]
      }]
    }
  end
end
