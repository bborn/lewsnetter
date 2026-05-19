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

  # ---------------------------------------------------------------------
  # PaperTrail audit-history wiring. EmailTemplate edits propagate to
  # every campaign that uses the template, so this audit trail is what
  # lets us answer "who changed the layout under that send?"
  # ---------------------------------------------------------------------
  test "paper_trail records a version on create" do
    assert_equal 1, @template.versions.count
    assert_equal "create", @template.versions.last.event
  end

  test "paper_trail records a version on update with the body diff" do
    new_body = "<mjml><mj-body><mj-section><mj-column><mj-text>Hello again</mj-text></mj-column></mj-section></mj-body></mjml>"
    assert_difference -> { @template.versions.count }, 1 do
      @template.update!(mjml_body: new_body)
    end
    v = @template.versions.last
    assert_equal "update", v.event
    changes = parse_paper_trail_changes(v.object_changes)
    assert_includes changes.keys, "mjml_body"
    assert_equal new_body, changes["mjml_body"][1]
  end

  test "paper_trail ignores updated_at-only saves" do
    assert_no_difference -> { @template.versions.count } do
      @template.touch
    end
  end

  test "paper_trail records a version on destroy" do
    id = @template.id
    @template.destroy!
    v = PaperTrail::Version.where(item_type: "EmailTemplate", item_id: id, event: "destroy").last
    assert_not_nil v
  end

  private

  def parse_paper_trail_changes(raw)
    return raw if raw.is_a?(Hash)
    YAML.safe_load(
      raw,
      permitted_classes: [Time, Date, DateTime, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Symbol]
    )
  end
end
