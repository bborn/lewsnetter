require "test_helper"

class SenderAddressTest < ActiveSupport::TestCase
  setup do
    @team = FactoryBot.create(:onboarded_user).current_team
  end

  test "requires an email" do
    sender = SenderAddress.new(team: @team, email: nil)
    refute sender.valid?
    assert_includes sender.errors[:email], "can't be blank"
  end

  # Regression for B10 (deep QA 2026-05-13): the model used to accept any
  # non-blank string as an email, so "not-an-email" round-tripped from the
  # form and showed up in the sender index. A bad sender address poisons SES
  # verification and breaks every campaign send.
  test "rejects values that aren't valid email addresses" do
    sender = SenderAddress.new(team: @team, email: "not-an-email")
    refute sender.valid?
    assert_includes sender.errors[:email], "must be a valid email address"
  end

  test "rejects values with whitespace" do
    sender = SenderAddress.new(team: @team, email: "foo @example.com")
    refute sender.valid?
    assert_includes sender.errors[:email], "must be a valid email address"
  end

  test "accepts a properly-formed email" do
    sender = SenderAddress.new(team: @team, email: "ok@example.com", name: "OK")
    assert sender.valid?, sender.errors.full_messages.inspect
  end

  test "destroying a sender address nullifies campaigns and sequences that reference it" do
    sender = FactoryBot.create(:sender_address, team: @team)
    campaign = FactoryBot.create(:campaign, team: @team, sender_address: sender)
    sequence = FactoryBot.create(:sequence, team: @team, sender_address: sender)
    step = FactoryBot.create(:sequence_step, sequence: sequence)

    assert_difference -> { SenderAddress.count }, -1 do
      sender.destroy!
    end

    assert_nil campaign.reload.sender_address_id
    assert_nil sequence.reload.sender_address_id
    assert_nil step.campaign.reload.sender_address_id
  end

  test "cannot delete the sender while a campaign is sending" do
    sender = create(:sender_address, team: @team)
    campaign = create(:campaign, team: @team, sender_address: sender, status: "sending")

    refute sender.destroy
    assert_match(/campaign/i, sender.errors.full_messages.to_sentence)
    assert_equal sender.id, campaign.reload.sender_address_id
  end
end
