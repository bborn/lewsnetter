require "test_helper"

class Account::Subscribers::ImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team
  end

  test "index renders" do
    get account_team_subscribers_imports_url(@team)
    assert_response :success
  end

  test "new renders" do
    get new_account_team_subscribers_import_url(@team)
    assert_response :success
  end

  # Regression for B2 (deep QA 2026-05-13): the gem's `shared/fields/file_field`
  # partial rendered the <input type=file> as `class="hidden"` waiting for a
  # Stimulus drop-zone that wasn't wired up, leaving no way for users to pick a
  # CSV. The form now renders an explicit visible file input.
  test "new exposes a visible CSV file input" do
    get new_account_team_subscribers_import_url(@team)
    assert_response :success
    assert_match(/<input[^>]+type="file"[^>]+name="subscribers_import\[csv\]"/, response.body)
    refute_match(/<input[^>]+type="file"[^>]+class="[^"]*\bhidden\b/, response.body,
      "CSV file input must not be hidden — users need to click it.")
  end

  test "create attaches the csv and runs the import job (inline test adapter)" do
    file = fixture_file_upload("sample_subscribers.csv", "text/csv")

    assert_difference -> { Subscribers::Import.count }, 1 do
      post account_team_subscribers_imports_url(@team),
        params: {subscribers_import: {csv: file, notes: "first batch"}}
    end

    import = Subscribers::Import.last
    assert_redirected_to account_subscribers_import_url(import)
    assert import.csv.attached?
    assert_equal "first batch", import.notes
    # With the inline adapter the job runs synchronously and we should land
    # in a terminal state with subscribers created.
    assert_includes %w[completed failed], import.reload.status
    assert_operator @team.subscribers.count, :>, 0
  end

  test "show renders" do
    import = @team.subscriber_imports.new(status: "completed",
      processed: 5, created_count: 4, updated_count: 1, error_count: 0)
    import.csv.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_subscribers.csv")),
      filename: "sample_subscribers.csv"
    )
    import.save!

    get account_subscribers_import_url(import)
    assert_response :success
  end
end
