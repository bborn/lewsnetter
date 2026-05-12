require "test_helper"

class Team::SesConfigurationTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @config = @team.build_ses_configuration(region: "us-east-1", status: "unconfigured")
  end

  test "accepts a valid unsubscribe_host" do
    @config.unsubscribe_host = "email.influencekit.com"
    assert @config.valid?, @config.errors.full_messages.to_sentence
  end

  test "accepts a blank unsubscribe_host" do
    @config.unsubscribe_host = ""
    assert @config.valid?, @config.errors.full_messages.to_sentence
  end

  test "accepts a nil unsubscribe_host" do
    @config.unsubscribe_host = nil
    assert @config.valid?, @config.errors.full_messages.to_sentence
  end

  test "rejects an unsubscribe_host with whitespace or punctuation" do
    @config.unsubscribe_host = "not a host!"
    refute @config.valid?
    assert_includes @config.errors.full_messages.to_sentence.downcase, "unsubscribe host"
  end

  test "rejects an unsubscribe_host longer than 253 characters" do
    @config.unsubscribe_host = ("a" * 254)
    refute @config.valid?
  end

  test "resolved_unsubscribe_host returns the configured host when present" do
    @config.unsubscribe_host = "email.influencekit.com"
    assert_equal "email.influencekit.com",
      @config.resolved_unsubscribe_host(default: "lewsnetter.whinynil.co")
  end

  test "resolved_unsubscribe_host falls back to default when blank" do
    @config.unsubscribe_host = ""
    assert_equal "lewsnetter.whinynil.co",
      @config.resolved_unsubscribe_host(default: "lewsnetter.whinynil.co")
  end

  test "resolved_unsubscribe_host falls back to default when nil" do
    @config.unsubscribe_host = nil
    assert_equal "lewsnetter.whinynil.co",
      @config.resolved_unsubscribe_host(default: "lewsnetter.whinynil.co")
  end
end
