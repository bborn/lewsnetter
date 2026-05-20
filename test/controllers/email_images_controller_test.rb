require "test_helper"

class EmailImagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @team = create(:team)
    @image = @team.email_images.new(
      content_type: "image/png", byte_size: 123, original_filename: "test-logo.png"
    )
    @image.file.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test-logo.png")),
      filename: "test-logo.png",
      content_type: "image/png"
    )
    @image.save!
  end

  def token_for(image)
    image.signed_id(purpose: EmailImage::SIGNED_ID_PURPOSE)
  end

  test "valid token 302-redirects to the blob URL" do
    get "/e/#{token_for(@image)}"

    assert_response :found
    assert response.location.present?, "expected a redirect target"
  end

  test "redirect is cacheable so repeat opens don't re-hit the app" do
    get "/e/#{token_for(@image)}"
    assert_match(/max-age=86400/, response.headers["Cache-Control"])
  end

  test "garbage token returns 404 (no leak, no error)" do
    get "/e/this-is-not-a-real-signed-id"
    assert_response :not_found
  end

  test "a token signed for a different purpose is rejected" do
    wrong = @image.signed_id(purpose: :something_else)
    get "/e/#{wrong}"
    assert_response :not_found
  end

  test "valid signature for a deleted image returns 404" do
    token = token_for(@image)
    @image.destroy!

    get "/e/#{token}"
    assert_response :not_found
  end

  test "resolves the token regardless of which host serves the request" do
    # The image URL is hosted on the team's branded email subdomain. The
    # controller resolves everything from the signed token, so the Host
    # header is irrelevant.
    get "/e/#{token_for(@image)}", headers: {"HTTP_HOST" => "email.influencekit.com"}
    assert_response :found
  end

  test "is reachable without authentication" do
    # No session is signed in here — an email client is not a logged-in
    # browser. A valid token must still resolve.
    get "/e/#{token_for(@image)}"
    assert_response :found
  end
end
