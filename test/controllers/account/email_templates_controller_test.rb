require "test_helper"

class Account::EmailTemplatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = FactoryBot.create(:onboarded_user)
    sign_in @user
    @team = @user.current_team

    @template = @team.email_templates.create!(
      name: "Welcome",
      mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi {{first_name}}</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
  end

  test "update attaches an image asset" do
    file = fixture_file_upload("test-logo.png", "image/png")

    assert_difference -> { @template.assets.count }, 1 do
      patch account_email_template_url(@template), params: {
        email_template: {assets: [file]}
      }
    end

    assert_redirected_to account_email_template_url(@template)
    @template.reload
    assert_predicate @template.assets, :attached?
  end

  test "update rejects a non-image asset" do
    file = fixture_file_upload("not-an-image.txt", "text/plain")

    patch account_email_template_url(@template), params: {
      email_template: {assets: [file]}
    }

    # Validation fails → renders :edit (422), no attachment persists.
    assert_response :unprocessable_entity
    @template.reload
    refute_predicate @template.assets, :attached?
  end

  # ---------------------------------------------------------------------
  # PaperTrail audit history is rendered on the show page, and whodunnit
  # must resolve back to the signed-in user's email. This test exercises
  # both the controller-level `set_paper_trail_whodunnit` wiring and the
  # `account/shared/_history.html.erb` partial.
  # ---------------------------------------------------------------------
  test "show page renders the Audit history section with the signed-in user as whodunnit" do
    # An update by the signed-in user — the `before_action` should stamp
    # current_user.id as the version's whodunnit.
    patch account_email_template_url(@template), params: {
      email_template: {name: "Welcome (v2)"}
    }
    @template.reload
    last_version = @template.versions.last
    assert_equal @user.id.to_s, last_version.whodunnit,
      "expected whodunnit to be set to current_user.id (got #{last_version.whodunnit.inspect})"

    get account_email_template_url(@template)
    assert_response :success
    assert_match(/Audit history/, response.body)
    # The History partial resolves whodunnit -> user email; the signed-in
    # user's email must show up at least once.
    assert_includes response.body, @user.email
  end

  # upload_asset now creates a standalone EmailImage (whose blob lives in the
  # permanent `public: true` email_media service) rather than attaching to
  # the template's `assets` collection, so the embedded URL outlives the
  # template. The JSON contract (`url`) is unchanged for the editor JS.
  test "upload_asset creates an EmailImage and returns a permanent URL" do
    file = fixture_file_upload("test-logo.png", "image/png")

    assert_difference -> { EmailImage.count }, 1 do
      assert_no_difference -> { @template.assets.count } do
        post upload_asset_account_email_template_url(@template), params: {file: file}
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body["url"].present?, "expected JSON to include a url"
    assert_equal "test-logo.png", body["name"]
    assert_equal "test-logo.png", body["filename"]
    assert_equal "image/png", body["content_type"]
    assert body["asset_id"].present?

    email_image = EmailImage.last
    assert_equal @team, email_image.team
    assert_equal body["asset_id"], email_image.id
    assert_predicate email_image.file, :attached?
  end

  test "upload_asset rejects a non-image file" do
    file = fixture_file_upload("not-an-image.txt", "text/plain")

    assert_no_difference -> { EmailImage.count } do
      post upload_asset_account_email_template_url(@template), params: {file: file}
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/image/i, body["error"])
  end

  test "upload_asset returns 422 when no file is provided" do
    post upload_asset_account_email_template_url(@template), params: {}

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/No file/i, body["error"])
  end

  test "upload_asset is scoped to teams the user can access" do
    other_user = FactoryBot.create(:onboarded_user)
    other_template = other_user.current_team.email_templates.create!(
      name: "Other team", mjml_body: "<mjml><mj-body></mj-body></mjml>"
    )

    file = fixture_file_upload("test-logo.png", "image/png")
    # Signed in as @user; posting to another team's template must be denied.
    post upload_asset_account_email_template_url(other_template), params: {file: file}
    refute_equal 200, response.status
  end

  test "destroy_asset purges the attachment" do
    @template.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test-logo.png")),
      filename: "test-logo.png",
      content_type: "image/png"
    )
    attachment = @template.assets.attachments.first
    assert_predicate @template.assets, :attached?

    # purge_later enqueues an ActiveStorage::PurgeJob; running it inline
    # via Sidekiq::Testing.inline! actually deletes the attachment, but
    # the request itself just needs to redirect cleanly + remove the
    # attachment row.
    delete asset_account_email_template_url(@template, asset_id: attachment.id)

    assert_redirected_to edit_account_email_template_url(@template)
    @template.reload
    refute_predicate @template.assets, :attached?
  end
end
