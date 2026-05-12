require "test_helper"

class SesSenderTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @sender = @team.sender_addresses.create!(
      email: "from@example.com", name: "Sender", verified: true, ses_status: "verified"
    )
    @template = @team.email_templates.create!(
      name: "T", mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
    @campaign = @team.campaigns.create!(
      email_template: @template,
      sender_address: @sender,
      subject: "Hello",
      body_mjml: @template.mjml_body,
      status: "draft"
    )
    @s1 = @team.subscribers.create!(email: "a@example.com", external_id: "ses-a", subscribed: true)
    @s2 = @team.subscribers.create!(email: "b@example.com", external_id: "ses-b", subscribed: true)
  end

  test "returns empty result for empty audience" do
    result = SesSender.send_bulk(campaign: @campaign, subscribers: [])
    assert_equal [], result.message_ids
    assert_equal [], result.failed
  end

  test "stub mode returns one message id per subscriber" do
    original = Rails.application.config.ses_client
    Rails.application.config.ses_client = :stub
    begin
      result = SesSender.send_bulk(campaign: @campaign, subscribers: [@s1, @s2])
      assert_equal 2, result.message_ids.size
      assert_empty result.failed
      assert(result.message_ids.all? { |id| id.start_with?("stub-") })
    ensure
      Rails.application.config.ses_client = original
    end
  end
end
