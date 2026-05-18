require "test_helper"

# Stubs Ses::ClientFor.call and .sns_client_for to return fake clients we
# can script (rather than using Aws::*::Client.new(stub_responses: true) —
# which works but doesn't let us record the exact request args sent).
#
# We track every call made to the fakes in a `:calls` array so each test
# can assert idempotency by counting calls after a re-run.
class Ses::SnsAutoWireTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )
    @webhook_url = "https://app.lewsnetter.dev/webhooks/ses/sns"
  end

  teardown do
    %i[call sns_client_for].each do |method_name|
      orig_name = :"_orig_#{method_name}"
      if Ses::ClientFor.singleton_class.method_defined?(orig_name)
        Ses::ClientFor.singleton_class.class_eval do
          alias_method method_name, orig_name
          remove_method orig_name
        end
      end
    end
  end

  test "creates topics, subscriptions, config set, and event destinations on a fresh team" do
    fake_ses = build_fake_ses(configuration_set_exists: false)
    fake_sns = build_fake_sns(existing_subscriptions_by_topic: Hash.new { |h, k| h[k] = [] })
    install_client_stubs(ses: fake_ses, sns: fake_sns)

    result = Ses::SnsAutoWire.new(team: @team, webhook_url: @webhook_url).call

    assert result.ok?, "expected ok, got error_message: #{result.error_message.inspect}"
    # All three topics should be created.
    assert_equal 3, fake_sns[:calls].count { |c| c[:op] == :create_topic }
    # All three subscriptions should be created (none existed).
    assert_equal 3, fake_sns[:calls].count { |c| c[:op] == :subscribe }
    # The configuration set didn't exist, so it should be created.
    assert fake_ses[:calls].any? { |c| c[:op] == :create_configuration_set }
    # One event destination per topic kind = 3 total.
    assert_equal 3, fake_ses[:calls].count { |c| c[:op] == :create_configuration_set_event_destination }

    config = @team.ses_configuration.reload
    assert_match(/lewsnetter-ses-bounces$/, config.sns_bounce_topic_arn.to_s)
    assert_match(/lewsnetter-ses-complaints$/, config.sns_complaint_topic_arn.to_s)
    assert_match(/lewsnetter-ses-deliveries$/, config.sns_delivery_topic_arn.to_s)

    # Result summary should mirror reality.
    assert_equal :created, result.summary[:configuration_set][:action]
    assert_equal :created, result.summary[:topics][:bounce][:action]
    assert_equal :created, result.summary[:subscriptions][:bounce][:action]
  end

  test "is idempotent: re-running with everything in place produces no new resources" do
    # First run: fresh state. Build mutable subscription store so the
    # subscribe call writes back into it for the second run to see.
    subscriptions_by_topic = Hash.new { |h, k| h[k] = [] }
    fake_ses = build_fake_ses(configuration_set_exists: false)
    fake_sns = build_fake_sns(existing_subscriptions_by_topic: subscriptions_by_topic)
    install_client_stubs(ses: fake_ses, sns: fake_sns)

    first = Ses::SnsAutoWire.new(team: @team, webhook_url: @webhook_url).call
    assert first.ok?
    # Subscribe writes back into the store so the second run sees them.
    fake_sns[:subscribe_calls].each do |call|
      subscriptions_by_topic[call[:topic_arn]] << OpenStruct.new(
        protocol: call[:protocol], endpoint: call[:endpoint],
        subscription_arn: "arn:aws:sns:us-east-1:1:sub-#{SecureRandom.hex(4)}"
      )
    end

    # Second run: configuration set now exists, subscriptions present, event
    # destinations already created — so the second run should call zero
    # subscribes, zero CreateConfigurationSet, and trigger the
    # AlreadyExists → UpdateConfigurationSetEventDestination branch.
    fake_ses2 = build_fake_ses(configuration_set_exists: true, event_destinations_exist: true)
    fake_sns2 = build_fake_sns(existing_subscriptions_by_topic: subscriptions_by_topic)
    install_client_stubs(ses: fake_ses2, sns: fake_sns2)

    second = Ses::SnsAutoWire.new(team: @team, webhook_url: @webhook_url).call

    assert second.ok?, "expected ok on re-run, got: #{second.error_message.inspect}"
    # No new subscriptions.
    assert_equal 0, fake_sns2[:calls].count { |c| c[:op] == :subscribe }
    # No new CreateConfigurationSet (existed).
    assert_equal 0, fake_ses2[:calls].count { |c| c[:op] == :create_configuration_set }
    # Event destinations existed → fell through to Update path.
    assert_equal 3, fake_ses2[:calls].count { |c| c[:op] == :update_configuration_set_event_destination }
    assert_equal :exists, second.summary[:configuration_set][:action]
    assert second.summary[:subscriptions].values.all? { |s| s[:action] == :exists }
  end

  test "returns ok: false with error_message when a step fails" do
    fake_ses = build_fake_ses(configuration_set_exists: false)
    fake_sns = build_fake_sns(existing_subscriptions_by_topic: Hash.new { |h, k| h[k] = [] })
    # Force CreateTopic to raise on the bounces topic only — partial
    # failure: complaints + deliveries should still wire up, but the
    # result is ok: false because something errored.
    fake_sns[:raise_on_create_topic_for] = "lewsnetter-ses-bounces"
    install_client_stubs(ses: fake_ses, sns: fake_sns)

    result = Ses::SnsAutoWire.new(team: @team, webhook_url: @webhook_url).call

    refute result.ok?
    assert_match(/topic\[bounce\]/, result.error_message)
    # The two surviving topics were still created.
    assert_equal :created, result.summary[:topics][:complaint][:action]
    assert_equal :created, result.summary[:topics][:delivery][:action]
    # And their ARNs were persisted.
    config = @team.ses_configuration.reload
    assert config.sns_complaint_topic_arn.present?
    assert config.sns_delivery_topic_arn.present?
    assert_nil config.sns_bounce_topic_arn
  end

  test "returns ok: false when team has no SES credentials" do
    @team.ses_configuration.update_columns(
      encrypted_access_key_id: nil,
      encrypted_secret_access_key: nil
    )

    result = Ses::SnsAutoWire.new(team: @team, webhook_url: @webhook_url).call
    refute result.ok?
    assert_match(/no SES configured|no SES/, result.error_message.to_s)
  end

  private

  # Build a stubbed SES (v2) client. Tracks every call into [:calls] so
  # tests can assert which ops fired. Behaviour toggles:
  #   :configuration_set_exists — GetConfigurationSet returns OK or raises NotFound
  #   :event_destinations_exist — CreateConfigurationSetEventDestination raises AlreadyExists
  def build_fake_ses(configuration_set_exists: false, event_destinations_exist: false)
    state = {
      calls: [],
      configuration_set_exists: configuration_set_exists,
      event_destinations_exist: event_destinations_exist
    }
    fake = Object.new
    fake.define_singleton_method(:get_configuration_set) do |args|
      state[:calls] << {op: :get_configuration_set, args: args}
      if state[:configuration_set_exists]
        OpenStruct.new(configuration_set_name: args[:configuration_set_name])
      else
        raise Aws::SESV2::Errors::NotFoundException.new(nil, "not found")
      end
    end
    fake.define_singleton_method(:create_configuration_set) do |args|
      state[:calls] << {op: :create_configuration_set, args: args}
      OpenStruct.new
    end
    fake.define_singleton_method(:create_configuration_set_event_destination) do |args|
      state[:calls] << {op: :create_configuration_set_event_destination, args: args}
      raise Aws::SESV2::Errors::AlreadyExistsException.new(nil, "already") if state[:event_destinations_exist]
      OpenStruct.new
    end
    fake.define_singleton_method(:update_configuration_set_event_destination) do |args|
      state[:calls] << {op: :update_configuration_set_event_destination, args: args}
      OpenStruct.new
    end
    state[:fake] = fake
    state.tap { |s| s.define_singleton_method(:method_missing) { |m, *a| fake.send(m, *a) } }
  end

  def build_fake_sns(existing_subscriptions_by_topic:)
    state = {
      calls: [],
      subscribe_calls: [],
      existing: existing_subscriptions_by_topic,
      raise_on_create_topic_for: nil
    }
    fake = Object.new
    fake.define_singleton_method(:create_topic) do |args|
      state[:calls] << {op: :create_topic, args: args}
      if state[:raise_on_create_topic_for] && args[:name] == state[:raise_on_create_topic_for]
        raise Aws::SNS::Errors::ServiceError.new(nil, "AccessDenied creating #{args[:name]}")
      end
      OpenStruct.new(topic_arn: "arn:aws:sns:us-east-1:123456789012:#{args[:name]}")
    end
    fake.define_singleton_method(:list_subscriptions_by_topic) do |args|
      state[:calls] << {op: :list_subscriptions_by_topic, args: args}
      OpenStruct.new(
        subscriptions: state[:existing][args[:topic_arn]] || [],
        next_token: nil
      )
    end
    fake.define_singleton_method(:subscribe) do |args|
      state[:calls] << {op: :subscribe, args: args}
      state[:subscribe_calls] << args
      OpenStruct.new(subscription_arn: "PendingConfirmation")
    end
    state[:fake] = fake
    state.tap { |s| s.define_singleton_method(:method_missing) { |m, *a| fake.send(m, *a) } }
  end

  def install_client_stubs(ses:, sns:)
    ses_fake = ses[:fake]
    sns_fake = sns[:fake]
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      alias_method :_orig_sns_client_for, :sns_client_for unless method_defined?(:_orig_sns_client_for)
      define_method(:call) { |_team| ses_fake }
      define_method(:sns_client_for) { |_team| sns_fake }
    end
  end
end
