require "test_helper"

class Account::SenderAddressesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
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

  test "create rejects user-supplied :verified and :ses_status, deriving them from SES" do
    install_ses_stub_returning("SUCCESS")

    post account_team_sender_addresses_url(@team), params: {
      sender_address: {
        email: "new@example.com",
        name: "New",
        # These should be dropped by strong params and overwritten by IdentityChecker.
        verified: false,
        ses_status: "hacker-supplied"
      }
    }

    assert_response :redirect
    record = SenderAddress.find_by(email: "new@example.com")
    assert record, "sender address should be created"
    assert_equal true, record.verified
    assert_equal "success", record.ses_status
  end

  test "create sets ses_status=not_in_ses when SES doesn't know the address" do
    install_ses_stub_raising(Aws::SESV2::Errors::NotFoundException.new(nil, "not found"))

    post account_team_sender_addresses_url(@team), params: {
      sender_address: {email: "stranger@example.com", name: "Stranger"}
    }

    assert_response :redirect
    record = SenderAddress.find_by(email: "stranger@example.com")
    assert_equal false, record.verified
    assert_equal "not_in_ses", record.ses_status
  end

  test "recheck route re-queries SES and updates the record" do
    sender_address = @team.sender_addresses.create!(
      email: "bruno@example.com", name: "Bruno", verified: false, ses_status: "pending"
    )
    install_ses_stub_returning("SUCCESS")

    post recheck_account_sender_address_url(sender_address)

    assert_response :redirect
    sender_address.reload
    assert_equal true, sender_address.verified
    assert_equal "success", sender_address.ses_status
  end

  test "show page renders read-only verified badge and recheck button" do
    sender_address = @team.sender_addresses.create!(
      email: "verified@example.com", name: "V", verified: true, ses_status: "success"
    )
    get account_sender_address_url(sender_address)
    assert_response :success
    assert_match(/Verified by SES/, response.body)
    assert_match(/Re-check with SES/, response.body)
  end

  test "show page renders unverified badge when verified is false" do
    sender_address = @team.sender_addresses.create!(
      email: "pending@example.com", name: "P", verified: false, ses_status: "pending"
    )
    get account_sender_address_url(sender_address)
    assert_response :success
    assert_match(/Not verified/, response.body)
    assert_match(/Verification pending/, response.body)
  end

  test "edit form omits :verified and :ses_status inputs" do
    sender_address = @team.sender_addresses.create!(
      email: "e@example.com", name: "E", verified: true, ses_status: "success"
    )
    get edit_account_sender_address_url(sender_address)
    assert_response :success
    assert_no_match(/name="sender_address\[verified\]"/, response.body)
    assert_no_match(/name="sender_address\[ses_status\]"/, response.body)
  end

  private

  def install_ses_stub_returning(status)
    fake = Object.new
    response = Struct.new(:verified_for_sending_status).new(status)
    fake.define_singleton_method(:get_email_identity) { |_| response }
    install_client_stub(fake)
  end

  def install_ses_stub_raising(error)
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
