require "test_helper"

class SuppressionTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  # ----- validations -----

  test "requires team, email, and reason" do
    suppression = Suppression.new
    assert_not suppression.valid?
    assert_includes suppression.errors[:team], "must exist"
    assert_includes suppression.errors[:email], "can't be blank"
    assert_includes suppression.errors[:reason], "can't be blank"
  end

  test "rejects unknown reasons" do
    suppression = Suppression.new(team: @team, email: "x@y.com", reason: "spite")
    assert_not suppression.valid?
    assert_includes suppression.errors[:reason], "is not included in the list"
  end

  test "rejects malformed emails" do
    suppression = Suppression.new(team: @team, email: "not-an-email", reason: "manual")
    assert_not suppression.valid?
    assert_includes suppression.errors[:email], "is invalid"
  end

  test "accepts each valid REASON" do
    Suppression::REASONS.each do |reason|
      s = Suppression.new(team: @team, email: "ok-#{reason}@example.com", reason: reason)
      assert s.valid?, "expected reason=#{reason} to be valid: #{s.errors.full_messages}"
    end
  end

  # ----- deterministic-encrypted email -----

  test "email is round-trip queryable via where(email:)" do
    Suppression.create!(team: @team, email: "Lookup@Example.com", reason: "manual")

    # Same email, different casing — should still hit the row thanks to
    # before_validation normalization + deterministic encryption.
    found = Suppression.where(team: @team, email: "lookup@example.com").first
    assert_not_nil found, "deterministic-encrypted lookup must find the row"
    assert_equal "lookup@example.com", found.email
  end

  test "email is normalized (downcased + stripped) before save" do
    s = Suppression.create!(team: @team, email: "   MiXeD@Example.COM ", reason: "manual")
    assert_equal "mixed@example.com", s.reload.email
  end

  # ----- uniqueness -----

  test "uniqueness is scoped per (team, email)" do
    Suppression.create!(team: @team, email: "dup@example.com", reason: "manual")
    dup = Suppression.new(team: @team, email: "dup@example.com", reason: "complaint")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "same email on a different team is allowed" do
    other = create(:team)
    Suppression.create!(team: @team, email: "shared@example.com", reason: "manual")
    s = Suppression.new(team: other, email: "shared@example.com", reason: "manual")
    assert s.valid?
  end

  # ----- .suppress (idempotent upsert) -----

  test "suppress creates a row on first call" do
    assert_difference -> { Suppression.count }, 1 do
      Suppression.suppress(team: @team, email: "first@example.com", reason: "hard_bounce", source: "General")
    end
    row = Suppression.find_by(team: @team, email: "first@example.com")
    assert_equal "hard_bounce", row.reason
    assert_equal "General", row.source
    assert_not_nil row.suppressed_at
  end

  test "suppress is idempotent — re-fires do not create dup rows or raise" do
    Suppression.suppress(team: @team, email: "dup@example.com", reason: "complaint", source: "abuse")
    assert_no_difference -> { Suppression.count } do
      Suppression.suppress(team: @team, email: "dup@example.com", reason: "complaint", source: "abuse")
      Suppression.suppress(team: @team, email: "DUP@example.com", reason: "complaint", source: "abuse")
    end
  end

  test "suppress preserves the original reason on re-fire" do
    # First fire: hard_bounce. Second fire: complaint (different event). We
    # keep the FIRST one because that's the more useful breadcrumb for "why
    # did this address get on the list?".
    Suppression.suppress(team: @team, email: "first@example.com", reason: "hard_bounce", source: "General")
    Suppression.suppress(team: @team, email: "first@example.com", reason: "complaint", source: "abuse")

    row = Suppression.find_by(team: @team, email: "first@example.com")
    assert_equal "hard_bounce", row.reason, "first reason wins"
    assert_equal "General", row.source
  end

  test "suppress returns nil for blank email" do
    assert_nil Suppression.suppress(team: @team, email: "", reason: "manual")
    assert_nil Suppression.suppress(team: @team, email: nil, reason: "manual")
  end

  # ----- .for_team_emails -----

  test "for_team_emails returns a Set of matching emails" do
    Suppression.create!(team: @team, email: "in@example.com", reason: "manual")
    Suppression.create!(team: @team, email: "alsoIN@example.com", reason: "complaint")

    result = Suppression.for_team_emails(@team, ["in@example.com", "ALSOIN@example.com", "not-on-list@example.com"])
    assert_kind_of Set, result
    assert_equal Set["in@example.com", "alsoin@example.com"], result
  end

  test "for_team_emails ignores other teams' rows" do
    other = create(:team)
    Suppression.create!(team: other, email: "wrongteam@example.com", reason: "manual")

    result = Suppression.for_team_emails(@team, ["wrongteam@example.com"])
    assert_empty result
  end

  test "for_team_emails returns an empty Set for empty input" do
    assert_equal Set.new, Suppression.for_team_emails(@team, [])
    assert_equal Set.new, Suppression.for_team_emails(@team, [nil, ""])
  end
end
