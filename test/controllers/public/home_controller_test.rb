require "test_helper"

class Public::HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_marketing_url = ENV["MARKETING_BASE_URL"]
    @original_app_url = ENV["APP_BASE_URL"]
    ENV.delete("MARKETING_BASE_URL")
    ENV.delete("APP_BASE_URL")
    host! "app.example.test"
    https!
  end

  teardown do
    ENV["MARKETING_BASE_URL"] = @original_marketing_url
    ENV["APP_BASE_URL"] = @original_app_url
  end

  test "the landing page renders on an app subdomain without a separate marketing host" do
    get "/"
    assert_response :ok
  end

  test "the app subdomain still redirects to the configured marketing host" do
    ENV["MARKETING_BASE_URL"] = "https://example.test"

    get "/"
    assert_response :moved_permanently
    assert_redirected_to "https://example.test/"
  end

  test "the landing page renders when marketing and app share an explicit host" do
    ENV["MARKETING_BASE_URL"] = "https://app.example.test"

    get "/"
    assert_response :ok
  end
end
