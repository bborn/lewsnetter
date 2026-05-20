require "test_helper"

class EmailImageTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  # Builds a valid EmailImage with the test-logo fixture attached. Uses the
  # `:test` disk service (config.active_storage.service = :test) — the
  # `service: :email_media` declared on the model is overridden in the test
  # environment so we never touch R2.
  def build_email_image(team: @team, filename: "test-logo.png", content_type: "image/png")
    image = team.email_images.new(
      content_type: content_type,
      byte_size: 123,
      original_filename: filename
    )
    image.file.attach(
      io: File.open(Rails.root.join("test/fixtures/files/#{filename}")),
      filename: filename,
      content_type: content_type
    )
    image
  end

  test "is valid with an attached image and content_type" do
    image = build_email_image
    assert image.valid?, image.errors.full_messages.to_sentence
    assert image.save
  end

  test "is invalid without an attached file" do
    image = @team.email_images.new(content_type: "image/png", byte_size: 1)
    refute image.valid?
    assert image.errors[:file].any? { |m| m =~ /attached/i },
      "expected a :file 'must be attached' error, got #{image.errors[:file].inspect}"
  end

  test "is invalid when the attached file is not an image" do
    image = build_email_image(filename: "not-an-image.txt", content_type: "text/plain")
    refute image.valid?
    assert image.errors[:file].any? { |m| m =~ /image/i },
      "expected a :file error mentioning 'image', got #{image.errors[:file].inspect}"
  end

  test "is invalid without a content_type" do
    image = build_email_image
    image.content_type = nil
    refute image.valid?
    assert image.errors[:content_type].any?
  end

  test "belongs to a team" do
    image = build_email_image
    image.save!
    assert_equal @team, image.team
  end

  # ---------------------------------------------------------------------
  # public_url — the permanent custom-domain URL baked into <mj-image src>.
  # ---------------------------------------------------------------------
  test "public_url builds a custom-domain URL off EMAIL_MEDIA_HOST" do
    image = build_email_image
    image.save!

    with_env("EMAIL_MEDIA_HOST" => "media.lewsnetter.dev") do
      url = image.public_url
      assert_equal "https://media.lewsnetter.dev/#{image.file.blob.key}", url
    end
  end

  test "public_url strips whitespace from EMAIL_MEDIA_HOST" do
    image = build_email_image
    image.save!

    with_env("EMAIL_MEDIA_HOST" => "  media.lewsnetter.dev  ") do
      assert_equal "https://media.lewsnetter.dev/#{image.file.blob.key}", image.public_url
    end
  end

  test "public_url falls back to the proxy URL when EMAIL_MEDIA_HOST is blank" do
    image = build_email_image
    image.save!

    with_env("EMAIL_MEDIA_HOST" => "") do
      url = image.public_url
      assert url.present?, "expected a fallback URL"
      # Falls back to the Active Storage proxy route rather than the
      # custom-domain host.
      assert_match(%r{/rails/active_storage/}, url,
        "expected the proxy-URL fallback, got #{url.inspect}")
    end
  end

  test "public_url returns nil when no file is attached" do
    image = @team.email_images.new(content_type: "image/png", byte_size: 1)
    assert_nil image.public_url
  end

  # ---------------------------------------------------------------------
  # The whole point of this model: email images must outlive everything.
  # Destroying a team must NOT cascade to its email_images.
  # ---------------------------------------------------------------------
  test "destroying a team does NOT destroy its email_images" do
    image = build_email_image
    image.save!
    image_id = image.id

    # Team#destroy cascades to subscribers, campaigns, templates, etc. —
    # but email_images is deliberately declared WITHOUT dependent: :destroy.
    @team.destroy

    assert EmailImage.exists?(image_id),
      "EmailImage was destroyed when its team was destroyed — it must survive " \
      "so already-sent emails keep working"
  end

  private

  def with_env(overrides)
    original = {}
    overrides.each do |k, v|
      original[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
