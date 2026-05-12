require "test_helper"

# IdentityChecker tests stub Ses::ClientFor.call by overriding the singleton
# method during the test block, then restoring it. Same pattern as the
# Verifier tests so we don't pull in WebMock or Mocha.
class Ses::IdentityCheckerTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )
    @sender_address = @team.sender_addresses.create!(
      email: "from@example.com",
      name: "From",
      verified: false,
      ses_status: "pending"
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

  test "sets verified=true and ses_status=success when SES returns SUCCESS" do
    stub_ses_client_returning(
      Struct.new(:verified_for_sending_status).new("SUCCESS")
    )

    Ses::IdentityChecker.new(sender_address: @sender_address).call
    @sender_address.reload

    assert_equal true, @sender_address.verified
    assert_equal "success", @sender_address.ses_status
  end

  test "sets verified=false and ses_status=pending when SES returns PENDING" do
    stub_ses_client_returning(
      Struct.new(:verified_for_sending_status).new("PENDING")
    )

    Ses::IdentityChecker.new(sender_address: @sender_address).call
    @sender_address.reload

    assert_equal false, @sender_address.verified
    assert_equal "pending", @sender_address.ses_status
  end

  test "sets verified=false and ses_status=not_in_ses on NotFoundException" do
    stub_ses_client_raising(Aws::SESV2::Errors::NotFoundException.new(nil, "Identity not found"))

    Ses::IdentityChecker.new(sender_address: @sender_address).call
    @sender_address.reload

    assert_equal false, @sender_address.verified
    assert_equal "not_in_ses", @sender_address.ses_status
  end

  test "sets verified=false and ses_status=error on generic AWS service error" do
    stub_ses_client_raising(Aws::SESV2::Errors::ServiceError.new(nil, "boom"))

    Ses::IdentityChecker.new(sender_address: @sender_address).call
    @sender_address.reload

    assert_equal false, @sender_address.verified
    assert_equal "error", @sender_address.ses_status
  end

  test "sets verified=false and ses_status=unconfigured when team has no SES" do
    @team.ses_configuration.update!(
      encrypted_access_key_id: nil,
      encrypted_secret_access_key: nil
    )

    Ses::IdentityChecker.new(sender_address: @sender_address).call
    @sender_address.reload

    assert_equal false, @sender_address.verified
    assert_equal "unconfigured", @sender_address.ses_status
  end

  private

  def stub_ses_client_returning(identity_response)
    fake = Object.new
    fake.define_singleton_method(:get_email_identity) { |_| identity_response }
    install_client_stub(fake)
  end

  def stub_ses_client_raising(error)
    fake = Object.new
    fake.define_singleton_method(:get_email_identity) { |_| raise error }
    install_client_stub(fake)
  end

  def install_client_stub(client)
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { |_team| client }
    end
  end
end
