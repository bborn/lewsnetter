require "test_helper"

class Ses::DomainIdentityCreatorTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:onboarded_user)
    @team = @user.current_team
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )
    @ses_domain = @team.create_ses_domain!(domain: "hey.example.com")
  end

  teardown do
    if Ses::ClientFor.singleton_class.method_defined?(:_orig_call)
      Ses::ClientFor.singleton_class.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
  end

  test "persists DKIM tokens and flips status to pending on success" do
    dkim = Struct.new(:tokens, :status).new(%w[abc def ghi], "PENDING")
    response = Struct.new(:dkim_attributes).new(dkim)

    fake = Object.new
    calls = []
    fake.define_singleton_method(:create_email_identity) do |args|
      calls << args
      response
    end
    install_client_stub(fake)

    result = Ses::DomainIdentityCreator.new(ses_domain: @ses_domain).call

    assert result.ok?
    assert_equal "pending", result.status
    assert_equal "pending", @ses_domain.reload.status
    assert_equal %w[abc def ghi], @ses_domain.dkim_token_list
    assert_equal "PENDING", @ses_domain.dkim_status
    assert_not_nil @ses_domain.last_verification_requested_at
    # Confirm we asked SES for the right identity + RSA_2048 key.
    assert_equal "hey.example.com", calls.first[:email_identity]
    assert_equal "RSA_2048_BIT", calls.first.dig(:dkim_signing_attributes, :next_signing_key_length)
  end

  test "treats AlreadyExistsException as success and hydrates from GetEmailIdentity" do
    dkim = Struct.new(:tokens, :status).new(%w[reused1 reused2 reused3], "SUCCESS")
    existing = Struct.new(:verification_status, :dkim_attributes).new("SUCCESS", dkim)

    fake = Object.new
    fake.define_singleton_method(:create_email_identity) do |_args|
      raise Aws::SESV2::Errors::AlreadyExistsException.new(nil, "already")
    end
    fake.define_singleton_method(:get_email_identity) do |_args|
      existing
    end
    install_client_stub(fake)

    result = Ses::DomainIdentityCreator.new(ses_domain: @ses_domain).call

    assert result.ok?
    # Hydrated from the GetEmailIdentity fallback.
    assert_equal "verified", @ses_domain.reload.status
    assert_equal %w[reused1 reused2 reused3], @ses_domain.dkim_token_list
    assert_not_nil @ses_domain.verified_at
  end

  test "returns unconfigured result when SES isn't set up" do
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { |_team| raise Ses::ClientFor::NotConfigured, "no config" }
    end

    result = Ses::DomainIdentityCreator.new(ses_domain: @ses_domain).call

    refute result.ok?
    assert_equal "unconfigured", result.status
  end

  test "wraps generic SES service errors into a friendly result" do
    fake = Object.new
    fake.define_singleton_method(:create_email_identity) do |_args|
      raise Aws::SESV2::Errors::ServiceError.new(nil, "boom")
    end
    install_client_stub(fake)

    result = Ses::DomainIdentityCreator.new(ses_domain: @ses_domain).call

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
