require "test_helper"

class Account::SegmentTranslationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  test "create responds 200 to a TURBO_STREAM request" do
    # Force stub mode so we never need an Anthropic key.
    AI::Base.force_stub = true
    begin
      post translate_account_team_segments_url(@team),
        params: {natural_language: "subscribers in California"},
        as: :turbo_stream
    ensure
      AI::Base.force_stub = false
    end

    assert_response :success
    assert_match(/text\/vnd\.turbo-stream\.html|text\/html/, response.media_type.to_s + response.content_type.to_s)
    # Critical regression assertion — the html partial must have rendered.
    assert_match(/Subscribers matching|stub mode|subscribed/, response.body)
  end

  test "create responds 200 to an HTML request (regression baseline)" do
    AI::Base.force_stub = true
    begin
      post translate_account_team_segments_url(@team),
        params: {natural_language: "subscribers in California"}
    ensure
      AI::Base.force_stub = false
    end

    assert_response :success
  end

  test "create responds with a JSON payload usable by the Stimulus controller" do
    @team.subscribers.create!(email: "a@example.com", name: "A", subscribed: true)
    @team.subscribers.create!(email: "b@example.com", name: "B", subscribed: true)
    AI::Base.force_stub = true
    begin
      post translate_account_team_segments_url(@team),
        params: {natural_language: "all subscribers"},
        as: :json
    ensure
      AI::Base.force_stub = false
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload.key?("sql_predicate"), "JSON shape should include sql_predicate"
    assert payload.key?("estimated_count"), "JSON shape should include estimated_count"
    assert payload.key?("sample_subscribers"), "JSON shape should include sample_subscribers"
    assert payload.key?("errors")
    assert payload["sample_subscribers"].is_a?(Array)
  end
end
