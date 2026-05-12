require "test_helper"

class Ses::ClientForTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  test "raises NotConfigured when team has no ses configuration" do
    assert_raises(Ses::ClientFor::NotConfigured) do
      Ses::ClientFor.call(@team)
    end
  end

  test "raises NotConfigured when configuration exists but credentials missing" do
    @team.create_ses_configuration!(region: "us-east-1", status: "unconfigured")
    assert_raises(Ses::ClientFor::NotConfigured) do
      Ses::ClientFor.call(@team)
    end
  end

  test "returns an SESV2 client when configured" do
    @team.create_ses_configuration!(
      region: "us-east-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )

    client = Ses::ClientFor.call(@team)
    assert_kind_of Aws::SESV2::Client, client
    assert_equal "us-east-1", client.config.region
  end

  test "sns_client_for returns an SNS client when configured" do
    @team.create_ses_configuration!(
      region: "eu-west-1",
      encrypted_access_key_id: "AKIATEST",
      encrypted_secret_access_key: "supersecret",
      status: "verified"
    )

    sns = Ses::ClientFor.sns_client_for(@team)
    assert_kind_of Aws::SNS::Client, sns
    assert_equal "eu-west-1", sns.config.region
  end

  test "sns_client_for raises NotConfigured when no ses configuration" do
    assert_raises(Ses::ClientFor::NotConfigured) do
      Ses::ClientFor.sns_client_for(@team)
    end
  end
end
