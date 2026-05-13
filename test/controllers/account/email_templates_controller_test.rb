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

  test "edit page renders the Assets section" do
    get edit_account_email_template_url(@template)
    assert_response :success
    # Heading + the multi-file picker name attribute MUST be present.
    assert_match(/Assets/, response.body)
    assert_select 'input[type="file"][name="email_template[assets][]"]', 1
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
