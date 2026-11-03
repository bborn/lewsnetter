require "test_helper"

# A sequence step's backing campaign is reachable by id through the MCP
# campaign tools and the campaigns API. Scheduling it would broadcast the step
# to its whole segment, so its status is locked and it only goes with its step.
class CampaignSequenceGuardTest < ActiveSupport::TestCase
  setup do
    @sequence = create(:sequence, :live)
    @team = @sequence.team
    @step = create(:sequence_step, sequence: @sequence, delay_minutes: 30)
    @campaign = @step.campaign
    @user = create(:onboarded_user)
    @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
  end

  test "the step's campaign is a sequence campaign" do
    assert_equal "sequence", @campaign.status
  end

  test "campaigns_schedule can't schedule a step's campaign" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Mcp::Tools::Campaigns::Schedule.new.invoke(
        arguments: {"id" => @campaign.id, "scheduled_for" => 1.day.from_now.iso8601},
        context: @ctx
      )
    end
    assert_equal "sequence", @campaign.reload.status
    assert_nil @campaign.scheduled_for
  end

  test "a step's campaign status can't change" do
    refute @campaign.update(status: "scheduled", scheduled_for: 1.day.from_now)
    assert @campaign.errors[:status].any?
    assert_equal "sequence", @campaign.reload.status
  end

  test "a regular campaign can't become a sequence campaign" do
    campaign = @team.campaigns.create!(subject: "Hi", status: "draft", body_markdown: "Hello")
    refute campaign.update(status: "sequence")
    assert campaign.errors[:status].any?
  end

  test "campaigns_delete can't delete a step's campaign" do
    assert_raises(ActiveRecord::RecordNotDestroyed) do
      Mcp::Tools::Campaigns::Delete.new.invoke(arguments: {"id" => @campaign.id}, context: @ctx)
    end
    assert Campaign.exists?(@campaign.id)
    assert_equal @campaign.id, @step.reload.campaign_id
  end

  test "removing the step still removes its campaign" do
    @step.destroy!
    refute Campaign.exists?(@campaign.id)
  end

  test "deleting the sequence removes its steps' campaigns" do
    @sequence.destroy!
    refute Campaign.exists?(@campaign.id)
  end
end
