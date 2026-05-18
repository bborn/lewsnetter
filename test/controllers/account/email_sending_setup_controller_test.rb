require "test_helper"

class Account::EmailSendingSetupControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  teardown do
    # Restore any class-level stubs the helpers installed.
    if Ses::Verifier.method_defined?(:_orig_call)
      Ses::Verifier.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
    if Ses::DomainIdentityCreator.method_defined?(:_orig_call)
      Ses::DomainIdentityCreator.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
    if Ses::DomainIdentityChecker.method_defined?(:_orig_call)
      Ses::DomainIdentityChecker.class_eval do
        alias_method :call, :_orig_call
        remove_method :_orig_call
      end
    end
  end

  test "show renders the credentials step for an unconfigured team" do
    get account_team_setup_email_sending_path(@team)
    assert_response :success
    assert_match(/Connect Amazon SES/i, @response.body)
    # Loops-aesthetic header on every step.
    assert_match(/Set up sending/i, @response.body)
  end

  test "show renders the domain step once credentials are verified" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIA",
      encrypted_secret_access_key: "s",
      status: "verified"
    )
    get account_team_setup_email_sending_path(@team)
    assert_response :success
    assert_match(/Sending domain/i, @response.body)
    assert_match(/Company postal address/i, @response.body)
    # CAN-SPAM hint line.
    assert_match(/CAN-SPAM/i, @response.body)
    # Loops-style subdomain advice.
    assert_match(/recommend a subdomain/i, @response.body)
  end

  test "show renders the verify_domain step once a pending domain exists" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")
    domain = @team.create_ses_domain!(domain: "hey.example.com", status: "pending")
    domain.dkim_token_list = %w[tokenA tokenB tokenC]
    domain.save!

    get account_team_setup_email_sending_path(@team)
    assert_response :success
    # All three CNAMEs render with the right host pattern.
    assert_match("tokenA._domainkey.hey.example.com", @response.body)
    assert_match("tokenA.dkim.amazonses.com", @response.body)
    assert_match("tokenC._domainkey.hey.example.com", @response.body)
    # DMARC tip is present.
    assert_match("_dmarc.hey.example.com", @response.body)
  end

  test "submit_domain persists the domain, postal address, and calls the identity creator" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")
    stub_domain_identity_creator_ok!

    post account_team_setup_domain_email_sending_path(@team), params: {
      team_ses_domain: {domain: "hey.example.com"},
      team_ses_configuration: {physical_postal_address: "123 Sand Hill Road, Menlo Park, CA 94025"}
    }
    assert_redirected_to account_team_setup_email_sending_path(@team)

    @team.reload
    assert_equal "hey.example.com", @team.ses_domain.domain
    assert_equal "pending", @team.ses_domain.status
    assert_equal "123 Sand Hill Road, Menlo Park, CA 94025", @team.ses_configuration.physical_postal_address
  end

  test "submit_domain stores postal address even when domain is blank" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")

    post account_team_setup_domain_email_sending_path(@team), params: {
      team_ses_domain: {domain: ""},
      team_ses_configuration: {physical_postal_address: "PO Box 42, San Francisco, CA"}
    }
    assert_response :unprocessable_entity
    assert_equal "PO Box 42, San Francisco, CA",
      @team.reload.ses_configuration.physical_postal_address
    assert_nil @team.reload.ses_domain
  end

  test "submit_domain re-renders with an inline error for an invalid hostname" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")

    post account_team_setup_domain_email_sending_path(@team), params: {
      team_ses_domain: {domain: "not a domain"},
      team_ses_configuration: {physical_postal_address: ""}
    }
    assert_response :unprocessable_entity
    assert_match(/hostname/i, flash[:alert] || @response.body)
  end

  test "domain_status returns the current state as JSON and triggers a check" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")
    domain = @team.create_ses_domain!(domain: "hey.example.com", status: "pending")
    domain.dkim_token_list = %w[a b c]
    domain.save!

    stub_domain_checker_state!("verified") do |stubbed_domain|
      stubbed_domain.update!(status: "verified", verified_at: Time.current)
    end

    get account_team_setup_domain_status_email_sending_path(@team)
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "verified", body["state"]
    assert body["checked"]
  end

  test "domain_status returns no_domain when team has not submitted one yet" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")
    get account_team_setup_domain_status_email_sending_path(@team)
    assert_response :success
    assert_equal "no_domain", JSON.parse(@response.body)["state"]
  end

  test "show renders the test step once domain is verified" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified")
    @team.create_ses_domain!(domain: "hey.example.com", status: "verified",
      verified_at: 1.hour.ago)

    get account_team_setup_email_sending_path(@team)
    assert_response :success
    assert_match(/Send a test/i, @response.body)
    assert_match("noreply@hey.example.com", @response.body)
  end

  test "show renders the done step after a test send" do
    @team.create_ses_configuration!(region: "us-east-1",
      encrypted_access_key_id: "AKIA", encrypted_secret_access_key: "s",
      status: "verified",
      last_test_sent_at: 1.minute.ago)
    @team.create_ses_domain!(domain: "hey.example.com", status: "verified",
      verified_at: 1.hour.ago)

    get account_team_setup_email_sending_path(@team)
    assert_response :success
    assert_match(/You're set up to send/i, @response.body)
  end

  private

  def stub_domain_identity_creator_ok!
    domain_holder = nil
    result_proc = ->(ses_domain) {
      ses_domain.update!(status: "pending", last_verification_requested_at: Time.current)
      ses_domain.dkim_token_list = %w[a b c]
      ses_domain.save!
      Ses::DomainIdentityCreator::Result.new(
        ok: true, status: "pending", message: "ok", ses_domain: ses_domain
      )
    }
    Ses::DomainIdentityCreator.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) {
        result_proc.call(@ses_domain)
      }
    end
  end

  def stub_domain_checker_state!(state, &mutator)
    Ses::DomainIdentityChecker.class_eval do
      alias_method :_orig_call, :call unless method_defined?(:_orig_call)
      define_method(:call) {
        mutator&.call(@ses_domain)
        Ses::DomainIdentityChecker::Result.new(ok: true, state: state, ses_domain: @ses_domain)
      }
    end
  end
end
