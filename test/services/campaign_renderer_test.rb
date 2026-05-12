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
end
