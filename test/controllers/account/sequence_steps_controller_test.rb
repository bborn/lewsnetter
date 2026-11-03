require "test_helper"

class Account::SequenceStepsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
    @team.update!(sequences_enabled: true)
    @sequence = FactoryBot.create(:sequence, team: @team)
  end

  test "new renders" do
    get new_account_sequence_sequence_step_url(@sequence)
    assert_response :success
    assert_select "input[name='sequence_step[subject]']"
  end

  test "create converts the delay amount + unit to minutes and builds the backing campaign" do
    assert_difference -> { @sequence.steps.count }, 1 do
      post account_sequence_sequence_steps_url(@sequence), params: {sequence_step: {
        subject: "Welcome", body_markdown: "Hello", delay_amount: "3", delay_unit: "days"
      }}
    end
    assert_redirected_to account_sequence_url(@sequence)
    step = @sequence.steps.last
    assert_equal 3 * 1440, step.delay_minutes
    assert_equal "sequence", step.campaign.status
    assert step.campaign.plain_text_only?
  end

  test "edit shows the delay in its largest even unit" do
    step = FactoryBot.create(:sequence_step, sequence: @sequence, delay_minutes: 120)
    get edit_account_sequence_step_url(step)
    assert_response :success
    assert_select "input[name='sequence_step[delay_amount]'][value='2']"
    assert_select "select[name='sequence_step[delay_unit]'] option[selected][value='hours']"
  end

  test "update re-renders with errors" do
    step = FactoryBot.create(:sequence_step, sequence: @sequence)
    patch account_sequence_step_url(step), params: {sequence_step: {subject: ""}}
    assert_response :unprocessable_entity
  end

  test "destroying a step pulls later enrollments back so nobody skips an email" do
    first = FactoryBot.create(:sequence_step, sequence: @sequence)
    FactoryBot.create(:sequence_step, sequence: @sequence)
    FactoryBot.create(:sequence_step, sequence: @sequence)
    at_third = @sequence.enrollments.create!(subscriber: FactoryBot.create(:subscriber, team: @team),
      state: "active", current_step: 2, next_send_at: 1.day.from_now, enrolled_at: Time.current)
    at_first = @sequence.enrollments.create!(subscriber: FactoryBot.create(:subscriber, team: @team),
      state: "active", current_step: 0, next_send_at: 1.day.from_now, enrolled_at: Time.current)

    delete account_sequence_step_url(first)
    assert_redirected_to account_sequence_url(@sequence)
    assert_equal 1, at_third.reload.current_step
    assert_equal 0, at_first.reload.current_step
    refute Campaign.exists?(first.campaign_id)
  end

  test "another team's step is not reachable" do
    other = FactoryBot.create(:sequence_step)
    get edit_account_sequence_step_url(other)
    assert_response :not_found
  end
end
