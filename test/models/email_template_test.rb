require "test_helper"

class EmailTemplateTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @template = @team.email_templates.create!(
      name: "T",
      mjml_body: "<mjml><mj-body><mj-section><mj-column><mj-text>Hi</mj-text></mj-column></mj-section></mj-body></mjml>"
    )
  end

  test "accepts an attached image asset" do
    @template.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test-logo.png")),
      filename: "test-logo.png",
      content_type: "image/png"
    )

    assert @template.valid?, @template.errors.full_messages.to_sentence
    assert_predicate @template.assets, :attached?
    assert_equal 1, @template.assets.count
  end

  test "rejects a non-image asset" do
    @template.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/not-an-image.txt")),
      filename: "not-an-image.txt",
      content_type: "text/plain"
    )

    refute @template.valid?
    # The custom validator surfaces a message that mentions "image".
    assert(@template.errors[:assets].any? { |m| m =~ /image/i },
      "expected an :assets error mentioning 'image', got #{@template.errors[:assets].inspect}")
  end

  test "rejects an asset that exceeds the size limit" do
    # Build an oversize blob without writing real bytes — we fake the
    # byte_size on the blob so we don't have to ship a 5 MB fixture.
    @template.assets.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test-logo.png")),
      filename: "huge.png",
      content_type: "image/png"
    )
    blob = @template.assets.last.blob
    blob.update_column(:byte_size, EmailTemplate::ASSET_MAX_BYTES + 1)

    refute @template.valid?
    assert(@template.errors[:assets].any? { |m| m =~ /smaller|MB|size/i },
      "expected a size error, got #{@template.errors[:assets].inspect}")
  end
end
