require "test_helper"

class Account::EmailSendingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  test "show renders the page even when no SES configuration exists yet" do
    get account_team_email_sending_path(@team)
    assert_response :success
    assert_match(/Email Sending/i, @response.body)
  end

  # Regression for B8 (deep QA 2026-05-13): the AWS field labels disappeared
  # because the form's `team_ses_configuration` scope didn't resolve a
  # `labels_for` lookup under the `email_sending.fields.*` locale namespace.
  # Pin explicit labels for every input so the form isn't a wall of bare
  # textboxes.
  test "show renders explicit labels for every AWS field" do
    get account_team_email_sending_path(@team)
    assert_response :success

    # SNS topic ARNs are auto-wired via Ses::SnsAutoWire (one-click button
    # on the show page) — no longer pasted by hand. They render read-only
    # on the show page once wired, but their labels don't appear in the
    # editable form anymore.
    expected_labels = [
      "AWS Access Key ID",
      "AWS Secret Access Key",
      "AWS Region",
      "SES Configuration Set",
      "Unsubscribe Host"
    ]

    expected_labels.each do |label|
      assert_match Regexp.new(Regexp.escape(label)), @response.body,
        "Expected '#{label}' label to render in the email_sending form."
    end
  end

  test "update accepts configuration_set_name" do
    stub_verifier_result(status: "verified", sandbox: false, quota_max: 50_000, quota_sent: 100)

    patch account_team_email_sending_path(@team), params: {
      team_ses_configuration: {
        encrypted_access_key_id: "AKIANEW",
        encrypted_secret_access_key: "secretnew",
        region: "us-west-2",
        configuration_set_name: "my-custom-set"
      }
    }

    config = @team.reload.ses_configuration
    assert_equal "my-custom-set", config.configuration_set_name
  end

  test "update saves credentials and triggers verification" do
    stub_verifier_result(status: "verified", sandbox: false, quota_max: 50_000, quota_sent: 100)

    patch account_team_email_sending_path(@team), params: {
      team_ses_configuration: {
        encrypted_access_key_id: "AKIANEW",
        encrypted_secret_access_key: "secretnew",
        region: "us-west-2"
      }
    }
    # Verified credentials redirect with `show_identities=1` so the show
    # action surfaces the Verified Identities panel without a second
    # network round-trip on cold loads.
    assert_redirected_to account_team_email_sending_path(@team, show_identities: 1)

    config = @team.reload.ses_configuration
    assert_equal "AKIANEW", config.encrypted_access_key_id
    assert_equal "us-west-2", config.region
    assert_equal "verified", config.status
    assert_equal 50_000, config.quota_max_send_24h
    assert_not_nil config.last_verified_at
  end

  test "verify writes the verifier result into the configuration" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "unconfigured"
    )
    stub_verifier_result(status: "verified", sandbox: true, quota_max: 200, quota_sent: 0)

    post account_team_verify_email_sending_path(@team)
    # On verified status, redirect with show_identities=1 (see controller).
    assert_redirected_to account_team_email_sending_path(@team, show_identities: 1)

    config = @team.reload.ses_configuration
    assert_equal "verified", config.status
    assert_equal 200, config.quota_max_send_24h
    assert_equal true, config.sandbox
  end

  test "verify with failed result records the status" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "unconfigured"
    )
    stub_verifier_result(status: "failed", error: "AccessDenied")

    post account_team_verify_email_sending_path(@team)
    assert_redirected_to account_team_email_sending_path(@team)

    config = @team.reload.ses_configuration
    assert_equal "failed", config.status
  end

  test "import_identity creates a sender address from a verified identity" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "verified"
    )

    assert_difference -> { @team.sender_addresses.count }, +1 do
      post account_team_import_identity_email_sending_path(@team),
        params: {identity: "hello@example.com"}
    end
    assert_redirected_to account_team_email_sending_path(@team)

    address = @team.sender_addresses.find_by(email: "hello@example.com")
    assert address.verified
    assert_equal "verified", address.ses_status
  end

  test "import_identity is idempotent on existing addresses" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "verified"
    )
    @team.sender_addresses.create!(email: "hello@example.com", verified: true, ses_status: "verified")

    assert_no_difference -> { @team.sender_addresses.count } do
      post account_team_import_identity_email_sending_path(@team),
        params: {identity: "hello@example.com"}
    end
  end

  test "update redirects to billing plan picker when team is not exempt and has no subscription" do
    # Temporarily flip the exempt list to something that won't match the
    # factory user's @example.com email — simulates a real paying customer
    # who hasn't subscribed yet.
    original = ENV["BILLING_EXEMPT_EMAILS"]
    ENV["BILLING_EXEMPT_EMAILS"] = "nobody@nowhere.invalid"
    begin
      patch account_team_email_sending_path(@team), params: {
        team_ses_configuration: {
          encrypted_access_key_id: "AKIANEW",
          encrypted_secret_access_key: "secretnew",
          region: "us-west-2"
        }
      }
      assert_redirected_to account_team_billing_subscriptions_path(@team)
      assert_match(/Pro subscription/i, flash[:alert])
      # And nothing was written.
      assert_nil @team.reload.ses_configuration
    ensure
      ENV["BILLING_EXEMPT_EMAILS"] = original
    end
  end

  test "update of non-credential fields is allowed without subscription" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "verified"
    )
    original = ENV["BILLING_EXEMPT_EMAILS"]
    ENV["BILLING_EXEMPT_EMAILS"] = "nobody@nowhere.invalid"
    begin
      patch account_team_email_sending_path(@team), params: {
        team_ses_configuration: {
          # No encrypted_* fields — just an unsubscribe_host change.
          unsubscribe_host: "email.example.com"
        }
      }
      assert_redirected_to account_team_email_sending_path(@team)
      assert_equal "email.example.com", @team.reload.ses_configuration.unsubscribe_host
    ensure
      ENV["BILLING_EXEMPT_EMAILS"] = original
    end
  end

  test "verify_sns calls Ses::SnsAutoWire and redirects with a notice" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "verified"
    )
    stub_sns_auto_wire_result(ok: true, summary: {
      configuration_set: {action: :created, name: "lewsnetter-default"},
      topics: {
        bounce: {arn: "arn:aws:sns:us-east-1:1:lewsnetter-ses-bounces", action: :created},
        complaint: {arn: "arn:aws:sns:us-east-1:1:lewsnetter-ses-complaints", action: :created},
        delivery: {arn: "arn:aws:sns:us-east-1:1:lewsnetter-ses-deliveries", action: :created}
      }
    })

    post account_team_verify_sns_email_sending_path(@team)
    assert_redirected_to account_team_email_sending_path(@team)
    assert_match(/SNS wiring complete/i, flash[:notice])
  end

  test "verify_sns surfaces service failures as a flash alert" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "verified"
    )
    stub_sns_auto_wire_result(ok: false, summary: {topics: {}, configuration_set: {}},
      error_message: "topic[bounce]: AccessDenied")

    post account_team_verify_sns_email_sending_path(@team)
    assert_redirected_to account_team_email_sending_path(@team)
    assert_match(/AccessDenied/, flash[:alert])
  end

  teardown do
    # Restore the original Verifier#call if a test stubbed it.
    if Ses::Verifier.method_defined?(:_orig_call)
      Ses::Verifier.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
    if Ses::SnsAutoWire.method_defined?(:_orig_call)
      Ses::SnsAutoWire.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
  end

  private

  # Stubs Ses::SnsAutoWire#call to return a canned Result.
  def stub_sns_auto_wire_result(ok:, summary:, error_message: nil)
    result = Ses::SnsAutoWire::Result.new(ok: ok, summary: summary, error_message: error_message)
    Ses::SnsAutoWire.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { result }
    end
  end

  # Stubs Ses::Verifier#call to return a canned result so controller tests
  # don't hit AWS. We swap the instance method via alias_method so the
  # teardown can restore it cleanly.
  def stub_verifier_result(status:, sandbox: false, quota_max: nil, quota_sent: nil, identities: [], error: nil)
    result = Ses::Verifier::Result.new(
      status: status, sandbox: sandbox, quota_max: quota_max,
      quota_sent: quota_sent, identities: identities, error: error
    )

    Ses::Verifier.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) { result }
    end
  end
end
