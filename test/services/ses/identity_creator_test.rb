require "test_helper"

class Ses::IdentityCreatorTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:onboarded_user)
    @team = @user.current_team
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )
    @sender_address = @team.sender_addresses.create!(
      email: "bruno@example.com",
      name: "Bruno",
      verified: false,
      ses_status: "not_in_ses"
    )
  end

  teardown do
    if Ses::ClientFor.singleton_class.method_defined?(:_orig_call)
      Ses::ClientFor.singleton_class.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
  end

  test "successfully creates a new SES identity and returns a sent result" do
    fake = Object.new
    calls = []
    fake.define_singleton_method(:create_email_identity) do |args|
      calls << args
      Object.new
    end
    install_client_stub(fake)

    result = Ses::IdentityCreator.new(sender_address: @sender_address).call

    assert result.ok?
    assert_equal "sent", result.status
    assert_equal [{email_identity: "bruno@example.com"}], calls
  end

  test "treats AlreadyExistsException as success" do
    fake = Object.new
    fake.define_singleton_method(:create_email_identity) do |_args|
      raise Aws::SESV2::Errors::AlreadyExistsException.new(nil, "already")
    end
    install_client_stub(fake)

    result = Ses::IdentityCreator.new(sender_address: @sender_address).call

    assert result.ok?
    assert_equal "already_exists", result.status
  end

  test "returns unconfigured result when SES isn't set up" do
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { |_team| raise Ses::ClientFor::NotConfigured, "no config" }
    end

    result = Ses::IdentityCreator.new(sender_address: @sender_address).call

    refute result.ok?
    assert_equal "unconfigured", result.status
  end

  test "wraps generic SES service errors into a friendly result" do
    fake = Object.new
    fake.define_singleton_method(:create_email_identity) do |_args|
      raise Aws::SESV2::Errors::ServiceError.new(nil, "boom")
    end
    install_client_stub(fake)

    result = Ses::IdentityCreator.new(sender_address: @sender_address).call

    refute result.ok?
    assert_equal "error", result.status
    assert_match(/boom/, result.message)
  end

  private

  def install_client_stub(client)
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { |_team| client }
    end
  end
end
