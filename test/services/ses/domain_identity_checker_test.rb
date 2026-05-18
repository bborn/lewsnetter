require "test_helper"

class Ses::DomainIdentityCheckerTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:onboarded_user)
    @team = @user.current_team
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )
    @ses_domain = @team.create_ses_domain!(
      domain: "hey.example.com",
      status: "pending",
      last_verification_requested_at: 1.minute.ago
    )
    @ses_domain.dkim_token_list = %w[tokenone tokentwo tokenthree]
    @ses_domain.save!
  end

  teardown do
    if Ses::ClientFor.singleton_class.method_defined?(:_orig_call)
      Ses::ClientFor.singleton_class.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
  end

  test "flips status to verified, sets verified_at, and provisions a default sender on SUCCESS" do
    dkim = Struct.new(:tokens, :status).new(%w[tokenone tokentwo tokenthree], "SUCCESS")
    identity = Struct.new(:verification_status, :dkim_attributes).new("SUCCESS", dkim)
    install_client_stub(get_email_identity: identity)

    result = nil
    assert_difference -> { @team.sender_addresses.count }, +1 do
      result = Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
    end
    assert result.ok?
    assert_equal "verified", result.state
    @ses_domain.reload
    assert_equal "verified", @ses_domain.status
    assert_not_nil @ses_domain.verified_at
    sender = @team.sender_addresses.find_by(email: "noreply@hey.example.com")
    assert sender.present?, "expected a default noreply@ sender to be provisioned"
    assert sender.verified
    assert_equal "domain_verified", sender.ses_status
  end

  test "stays pending while DKIM is still propagating" do
    dkim = Struct.new(:tokens, :status).new(%w[tokenone tokentwo tokenthree], "PENDING")
    identity = Struct.new(:verification_status, :dkim_attributes).new("PENDING", dkim)
    install_client_stub(get_email_identity: identity)

    assert_no_difference -> { @team.sender_addresses.count } do
      result = Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
      assert_equal "pending", result.state
    end
    assert_equal "pending", @ses_domain.reload.status
    assert_nil @ses_domain.verified_at
  end

  test "marks as failed when DKIM reports FAILED" do
    dkim = Struct.new(:tokens, :status).new([], "FAILED")
    identity = Struct.new(:verification_status, :dkim_attributes).new("PENDING", dkim)
    install_client_stub(get_email_identity: identity)

    result = Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
    assert_equal "failed", result.state
    assert_equal "failed", @ses_domain.reload.status
  end

  test "does not double-provision a sender if one already exists on this domain" do
    @team.sender_addresses.create!(email: "marketing@hey.example.com",
      verified: true, ses_status: "verified")

    dkim = Struct.new(:tokens, :status).new(%w[tokenone tokentwo tokenthree], "SUCCESS")
    identity = Struct.new(:verification_status, :dkim_attributes).new("SUCCESS", dkim)
    install_client_stub(get_email_identity: identity)

    assert_no_difference -> { @team.sender_addresses.count } do
      Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
    end
  end

  test "rolls back to unverified when SES no longer knows the identity" do
    fake = Object.new
    fake.define_singleton_method(:get_email_identity) do |_args|
      raise Aws::SESV2::Errors::NotFoundException.new(nil, "gone")
    end
    install_client_stub_with_fake(fake)

    result = Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
    assert result.ok?
    assert_equal "unverified", result.state
    assert_equal "unverified", @ses_domain.reload.status
  end

  test "returns ok=false but does not raise when SES errors out" do
    fake = Object.new
    fake.define_singleton_method(:get_email_identity) do |_args|
      raise Aws::SESV2::Errors::ServiceError.new(nil, "boom")
    end
    install_client_stub_with_fake(fake)

    result = Ses::DomainIdentityChecker.new(ses_domain: @ses_domain).call
    refute result.ok?
    assert_equal "error", result.state
    assert_match(/boom/, result.error)
  end

  private

  def install_client_stub(get_email_identity:)
    fake = Object.new
    fake.define_singleton_method(:get_email_identity) { |_args| get_email_identity }
    install_client_stub_with_fake(fake)
  end

  def install_client_stub_with_fake(fake)
    Ses::ClientFor.singleton_class.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { |_team| fake }
    end
  end
end
