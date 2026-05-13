require "test_helper"

# Verifier tests stub Ses::ClientFor.call by overriding the singleton method
# during the test block, then restoring it. Doing this without WebMock or
# Mocha keeps the dependency footprint small.
class Ses::VerifierTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "unconfigured"
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

  test "returns verified status with quota + identities on success" do
    account = Struct.new(:production_access_enabled, :send_quota).new(
      true,
      Struct.new(:max_24_hour_send, :sent_last_24_hours).new(50_000.0, 1234.0)
    )
    identities = [
      Struct.new(:identity_name, :identity_type, :sending_enabled, :verification_status).new(
        "newsletter@example.com", "EMAIL_ADDRESS", true, "SUCCESS"
      )
    ]
    stub_ses_client(
      get_account: account,
      list_email_identities: Struct.new(:email_identities).new(identities)
    )

    result = Ses::Verifier.new(team: @team).call
    assert_equal "verified", result.status
    assert_equal false, result.sandbox # production_access_enabled was true
    assert_equal 50_000, result.quota_max
    assert_equal 1234, result.quota_sent
    assert_equal 1, result.identities.size
    assert_equal "newsletter@example.com", result.identities.first[:identity]
    assert_nil result.error
  end

  test "reports sandbox when production access is disabled" do
    account = Struct.new(:production_access_enabled, :send_quota).new(
      false,
      Struct.new(:max_24_hour_send, :sent_last_24_hours).new(200.0, 5.0)
    )
    stub_ses_client(
      get_account: account,
      list_email_identities: Struct.new(:email_identities).new([])
    )

    result = Ses::Verifier.new(team: @team).call
    assert_equal true, result.sandbox
  end

  test "returns failed status with error message on SES error" do
    error = Aws::SESV2::Errors::ServiceError.new(nil, "Invalid credentials")
    stub_ses_client_raising(error)

    result = Ses::Verifier.new(team: @team).call
    assert_equal "failed", result.status
    assert_match(/Invalid credentials/, result.error)
    assert_equal [], result.identities
  end

  test "returns unconfigured status when team has no credentials" do
    @team.ses_configuration.update!(
      encrypted_access_key_id: nil,
      encrypted_secret_access_key: nil
    )
    result = Ses::Verifier.new(team: @team).call
    assert_equal "unconfigured", result.status
    assert_match(/has no SES configured/, result.error)
  end

  private

  def stub_ses_client(get_account:, list_email_identities:)
    fake = Object.new
    fake.define_singleton_method(:get_account) { get_account }
    fake.define_singleton_method(:list_email_identities) { list_email_identities }
    install_client_stub(fake)
  end

  def stub_ses_client_raising(error)
    fake = Object.new
    fake.define_singleton_method(:get_account) { raise error }
    fake.define_singleton_method(:list_email_identities) { raise error }
    install_client_stub(fake)
  end

  def install_client_stub(client)
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { |_team| client }
    end
  end
end
