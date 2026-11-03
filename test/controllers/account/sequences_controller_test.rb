require "test_helper"

class Account::SequencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
    @team.update!(sequences_enabled: true)
    @sender = FactoryBot.create(:sender_address, team: @team, verified: true, ses_status: "verified")
  end

  # A 404 rendered from a raised exception doesn't write the session cookie,
  # so sign back in before each follow-up request.
  test "every page 404s while the team flag is off" do
    sequence = FactoryBot.create(:sequence, team: @team)
    @team.update!(sequences_enabled: false)

    get account_team_sequences_url(@team)
    assert_response :not_found
    sign_in @user
    get account_sequence_url(sequence)
    assert_response :not_found
    sign_in @user
    get new_account_sequence_sequence_step_url(sequence)
    assert_response :not_found
  end

  test "menu shows Sequences only when the flag is on" do
    get account_team_sequences_url(@team)
    assert_select "a[href=?]", account_team_sequences_path(@team)

    @team.update!(sequences_enabled: false)
    get account_team_suppressions_url(@team)
    assert_select "a[href=?]", account_team_sequences_path(@team), count: 0
  end

  test "index lists sequences with enrollment counts" do
    sequence = FactoryBot.create(:sequence, team: @team, name: "Welcome series")
    FactoryBot.create(:sequence_step, sequence: sequence)
    2.times do
      sequence.enrollments.create!(subscriber: FactoryBot.create(:subscriber, team: @team),
        state: "active", current_step: 0, next_send_at: 1.day.from_now, enrolled_at: Time.current)
    end

    get account_team_sequences_url(@team)
    assert_response :success
    assert_match "Welcome series", response.body
    assert_select "td", text: "2"
  end

  test "create, then the show page renders per-step counts" do
    assert_difference -> { @team.sequences.count }, 1 do
      post account_team_sequences_url(@team), params: {sequence: {
        name: "Trial nudges", trigger_type: "event", trigger_event_name: "trial_started",
        status: "draft", sender_address_id: @sender.id, reentry_days: ""
      }}
    end
    sequence = @team.sequences.last
    assert_redirected_to account_sequence_url(sequence)
    assert_nil sequence.reentry_days

    step = FactoryBot.create(:sequence_step, sequence: sequence, subject: "Day one")
    subscriber = FactoryBot.create(:subscriber, team: @team)
    sequence.enrollments.create!(subscriber: subscriber, state: "active", current_step: 0,
      next_send_at: Time.current, enrolled_at: Time.current)
    step.campaign.deliveries.create!(subscriber: subscriber, status: "delivered", ses_message_id: "msg-1",
      sent_at: 1.hour.ago, delivered_at: 50.minutes.ago)

    get account_sequence_url(sequence)
    assert_response :success
    assert_select "tr[data-step-position='1']" do
      assert_select "td", text: /Day one/
      assert_select "td[data-stat='waiting']", text: "1"
      assert_select "td[data-stat='sent']", text: "1"
      assert_select "td[data-stat='delivered']", text: "1"
    end
    assert_select "[data-enrollment-state='active']", text: /1/
  end

  test "create re-renders with errors" do
    post account_team_sequences_url(@team), params: {sequence: {name: "", trigger_type: "event"}}
    assert_response :unprocessable_entity
    assert_match "Name can", response.body
  end

  test "activate and pause from the show page" do
    sequence = FactoryBot.create(:sequence, team: @team, sender_address: @sender)
    FactoryBot.create(:sequence_step, sequence: sequence)

    patch account_sequence_url(sequence), params: {sequence: {status: "active"}}
    assert_redirected_to account_sequence_url(sequence)
    assert sequence.reload.active?

    patch account_sequence_url(sequence), params: {sequence: {status: "paused"}}
    assert sequence.reload.paused?
  end

  test "activating without a sender fails" do
    sequence = FactoryBot.create(:sequence, team: @team)
    patch account_sequence_url(sequence), params: {sequence: {status: "active"}}
    assert_response :unprocessable_entity
    assert sequence.reload.draft?
  end

  test "another team's sequence is not reachable" do
    other = FactoryBot.create(:sequence)
    get account_sequence_url(other)
    assert_response :not_found
    sign_in @user
    delete account_sequence_url(other)
    assert_response :not_found
    assert Sequence.exists?(other.id)
  end

  test "destroy removes the sequence" do
    sequence = FactoryBot.create(:sequence, team: @team)
    delete account_sequence_url(sequence)
    assert_redirected_to account_team_sequences_url(@team)
    refute Sequence.exists?(sequence.id)
  end
end
