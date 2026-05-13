require "test_helper"

class CampaignRendererTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @sender = @team.sender_addresses.create!(
      email: "from@example.com", name: "Sender", verified: true, ses_status: "verified"
    )
    @template = @team.email_templates.create!(
      name: "T",
      mjml_body: <<~MJML
        <mjml>
          <mj-body>
            <mj-section>
              <mj-column>
                <mj-text>Hello {{first_name}} on the {{plan}} plan ({{email}}).</mj-text>
              </mj-column>
            </mj-section>
          </mj-body>
        </mjml>
      MJML
    )
    @campaign = @team.campaigns.create!(
      email_template: @template,
      sender_address: @sender,
      subject: "Hi {{first_name}}",
      preheader: "Quick note for {{first_name}}",
      body_mjml: @template.mjml_body,
      status: "draft"
    )
    @subscriber = @team.subscribers.create!(
      email: "alice@example.com",
      external_id: "renderer-1",
      name: "Alice Smith",
      subscribed: true,
      custom_attributes: {"plan" => "growth"}
    )
  end

  test "substitutes variables in subject and preheader" do
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_equal "Hi Alice", result.subject
    assert_equal "Quick note for Alice", result.preheader
  end

  test "substitutes variables and compiles MJML to inlined HTML" do
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_includes result.html, "Hello Alice on the growth plan"
    assert_includes result.html, "alice@example.com"
    # Premailer inlines styles — there should be inline style attributes on
    # the HTML elements MJML emits.
    assert_match(/style="/, result.html)
  end

  test "produces a stripped plain-text version" do
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_includes result.text, "Hello Alice on the growth plan"
    refute_match(/<[a-z]/i, result.text)
  end

  test "leaves unknown variables in place so the user notices" do
    @campaign.update!(subject: "Hello {{unknown_var}}")
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_equal "Hello {{unknown_var}}", result.subject
  end

  test "falls back to the email_template body when body_mjml is blank" do
    @campaign.update_columns(body_mjml: nil)
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_includes result.html, "Hello Alice on the growth plan"
  end

  test "raises when both body_mjml and template body are missing" do
    @campaign.update_columns(body_mjml: nil)
    @template.update_columns(mjml_body: nil)
    assert_raises(RuntimeError) do
      CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    end
  end

  test "handles single-name subscribers without exploding" do
    @subscriber.update!(name: "Cher")
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_equal "Hi Cher", result.subject
    # last_name substitution should resolve to "" rather than leaving {{last_name}}
    refute_includes result.html, "{{last_name}}"
  end

  test "substitutes {{unsubscribe_url}} with a per-recipient signed URL" do
    @campaign.update!(body_mjml: <<~MJML)
      <mjml>
        <mj-body>
          <mj-section>
            <mj-column>
              <mj-text>
                Hi {{first_name}} —
                <a href="{{unsubscribe_url}}">unsubscribe</a>
              </mj-text>
            </mj-column>
          </mj-section>
        </mj-body>
      </mjml>
    MJML

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call

    refute_includes result.html, "{{unsubscribe_url}}",
      "expected {{unsubscribe_url}} token to be substituted"
    assert_match %r{https://[^"\s]+/unsubscribe/[^"\s]+}, result.html
  end

  test "markdown body is compiled through the template's {{body}} placeholder" do
    @template.update!(mjml_body: <<~MJML)
      <mjml>
        <mj-body>
          <mj-section><mj-column><mj-text>BRAND HEADER</mj-text></mj-column></mj-section>
          {{body}}
          <mj-section><mj-column><mj-text>FOOTER · <a href="{{unsubscribe_url}}">unsubscribe</a></mj-text></mj-column></mj-section>
        </mj-body>
      </mjml>
    MJML
    @campaign.update!(
      body_markdown: "## Hello {{first_name}}\n\nWelcome to the **{{plan}}** plan.\n\n[Get started →](https://example.com/start)",
      body_mjml: nil
    )

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call

    # Body content from markdown is present, rendered as HTML headings + paragraphs.
    assert_includes result.html, "Hello Alice"
    assert_includes result.html, "<h2"
    assert_includes result.html, "Welcome to the"
    assert_includes result.html, "<strong>growth</strong>"
    assert_includes result.html, "Get started"
    assert_includes result.html, "https://example.com/start"

    # Chrome (header + footer) from the template is also present, surrounding the body.
    assert_includes result.html, "BRAND HEADER"
    assert_includes result.html, "FOOTER"

    # Unsubscribe URL still got substituted in the footer.
    refute_includes result.html, "{{unsubscribe_url}}"
    assert_match %r{/unsubscribe/}, result.html

    # The body markdown landed BEFORE the footer (correct slot order).
    assert result.html.index("Hello Alice") < result.html.index("FOOTER"),
      "expected markdown body to render before the template footer"
    # And AFTER the header.
    assert result.html.index("BRAND HEADER") < result.html.index("Hello Alice"),
      "expected template header to render before the markdown body"
  end

  test "markdown body without {{body}} placeholder falls back to appending before </mj-body>" do
    @template.update!(mjml_body: <<~MJML)
      <mjml>
        <mj-body>
          <mj-section><mj-column><mj-text>TEMPLATE TOP</mj-text></mj-column></mj-section>
        </mj-body>
      </mjml>
    MJML
    @campaign.update!(
      body_markdown: "## Markdown heading\n\nSome content.",
      body_mjml: nil
    )

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call

    assert_includes result.html, "TEMPLATE TOP"
    assert_includes result.html, "Markdown heading"
    assert result.html.index("TEMPLATE TOP") < result.html.index("Markdown heading")
  end

  test "markdown body strips unsafe HTML (no raw script tags)" do
    @template.update!(mjml_body: "<mjml><mj-body>{{body}}</mj-body></mjml>")
    @campaign.update!(
      body_markdown: "## Safe\n\n<script>alert('xss')</script>\n\n<iframe src=\"http://evil.com\"></iframe>",
      body_mjml: nil
    )

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call

    refute_includes result.html, "<script>"
    refute_includes result.html, "alert("
    refute_includes result.html, "<iframe"
  end

  test "markdown path takes priority over body_mjml when both are present" do
    @template.update!(mjml_body: "<mjml><mj-body>{{body}}</mj-body></mjml>")
    @campaign.update!(
      body_markdown: "## From markdown\n\nThis is the markdown body.",
      body_mjml: "<mjml><mj-body><mj-section><mj-column><mj-text>From legacy MJML</mj-text></mj-column></mj-section></mj-body></mjml>"
    )

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call

    assert_includes result.html, "From markdown"
    refute_includes result.html, "From legacy MJML"
  end

  test "{{unsubscribe_url}} substitution honors the team's unsubscribe_host" do
    @team.build_ses_configuration(
      region: "us-east-1",
      status: "verified",
      unsubscribe_host: "email.influencekit.com"
    ).save!

    @campaign.update!(body_mjml: <<~MJML)
      <mjml>
        <mj-body>
          <mj-section>
            <mj-column>
              <mj-text><a href="{{unsubscribe_url}}">u</a></mj-text>
            </mj-column>
          </mj-section>
        </mj-body>
      </mjml>
    MJML

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber.reload).call
    assert_includes result.html, "email.influencekit.com/unsubscribe/"
  end

  test "{{key|fallback}} uses the value when the variable is present" do
    @campaign.update!(subject: "Hi {{first_name|there}}")
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_equal "Hi Alice", result.subject
  end

  test "{{key|fallback}} uses the fallback when the value is blank" do
    @subscriber.update!(name: "")
    @campaign.update!(subject: "Hi {{first_name|there}}")
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_equal "Hi there", result.subject
  end

  test "{{key|fallback}} uses the fallback when the variable is unknown" do
    @campaign.update!(subject: "Status: {{nonexistent_attr|n/a}}")
    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber).call
    assert_equal "Status: n/a", result.subject
  end

  test "{{key|fallback}} interpolates correctly inside a markdown URL" do
    @template.update!(mjml_body: <<~MJML)
      <mjml>
        <mj-body>
          {{body}}
        </mj-body>
      </mjml>
    MJML
    # Subscriber has no `subdomain` custom attribute → fallback "app" should
    # be used in place of the missing value inside the link URL.
    @campaign.update!(
      body_mjml: nil,
      body_markdown: "Visit your [dashboard](https://{{subdomain|app}}.influencekit.com/login)."
    )

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber.reload).call

    assert_includes result.html, "https://app.influencekit.com/login",
      "expected {{subdomain|app}} fallback to render inside the markdown URL"
    refute_includes result.html, "%7Bsubdomain",
      "expected no URL-encoded braces in the rendered href"
  end

  test "interpolates {{custom_attribute}} inside a markdown link URL" do
    # Use a template that hosts a {{body}} placeholder so the markdown path
    # is exercised (rather than the legacy body_mjml path).
    @template.update!(mjml_body: <<~MJML)
      <mjml>
        <mj-body>
          {{body}}
        </mj-body>
      </mjml>
    MJML
    @subscriber.update!(custom_attributes: {"subdomain" => "acme"})
    @campaign.update!(
      body_mjml: nil,
      body_markdown: "Visit your [dashboard](https://{{subdomain}}.influencekit.com/login)."
    )

    result = CampaignRenderer.new(campaign: @campaign, subscriber: @subscriber.reload).call

    assert_includes result.html, "https://acme.influencekit.com/login",
      "expected the {{subdomain}} placeholder to be interpolated inside the markdown link URL"
    refute_includes result.html, "%7Bsubdomain%7D",
      "expected no URL-encoded braces in the rendered href"
  end
end
