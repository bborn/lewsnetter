require "test_helper"

class UnsubscribeUrlHelperTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @subscriber = @team.subscribers.create!(
      email: "alice@example.com",
      external_id: "helper-#{SecureRandom.hex(4)}",
      name: "Alice",
      subscribed: true
    )
  end

  test "uses the team's unsubscribe_host when set" do
    @team.build_ses_configuration(
      region: "us-east-1",
      status: "verified",
      unsubscribe_host: "email.influencekit.com"
    ).save!

    url = UnsubscribeUrlHelper.url_for(
      subscriber: @subscriber.reload,
      default_host: "lewsnetter.whinynil.co"
    )

    assert url.start_with?("https://email.influencekit.com/unsubscribe/"),
      "expected URL to use team host, got #{url}"
  end

  test "falls back to default_host when team SES config has blank unsubscribe_host" do
    @team.build_ses_configuration(
      region: "us-east-1",
      status: "verified",
      unsubscribe_host: ""
    ).save!

    url = UnsubscribeUrlHelper.url_for(
      subscriber: @subscriber.reload,
      default_host: "lewsnetter.whinynil.co"
    )

    assert url.start_with?("https://lewsnetter.whinynil.co/unsubscribe/"),
      "expected URL to use default host, got #{url}"
  end

  test "falls back to default_host when team has no SES config at all" do
    assert_nil @team.ses_configuration

    url = UnsubscribeUrlHelper.url_for(
      subscriber: @subscriber,
      default_host: "lewsnetter.whinynil.co"
    )

    assert url.start_with?("https://lewsnetter.whinynil.co/unsubscribe/"),
      "expected URL to use default host, got #{url}"
  end

  test "falls back to action_mailer default_url_options when no default_host given" do
    expected_host = Rails.application.config.action_mailer.default_url_options[:host]
    url = UnsubscribeUrlHelper.url_for(subscriber: @subscriber)

    assert url.start_with?("https://#{expected_host}/unsubscribe/"),
      "expected URL to use action_mailer default host #{expected_host}, got #{url}"
  end

  test "embeds a Rails signed GlobalID that the unsubscribe locator resolves" do
    url = UnsubscribeUrlHelper.url_for(
      subscriber: @subscriber,
      default_host: "lewsnetter.whinynil.co"
    )

    token = url.split("/unsubscribe/").last
    located = GlobalID::Locator.locate_signed(token, for: "unsubscribe")

    assert_equal @subscriber, located
  end
end
