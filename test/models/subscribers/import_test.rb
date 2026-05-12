require "test_helper"

class Subscribers::ImportTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  test "requires a status from the allowed list" do
    import = Subscribers::Import.new(team: @team, status: "bogus")
    import.csv.attach(io: StringIO.new("email\nfoo@example.com\n"), filename: "x.csv")
    assert_not import.valid?
    assert import.errors[:status].any?
  end

  test "requires an attached csv" do
    import = Subscribers::Import.new(team: @team)
    assert_not import.valid?
    assert import.errors[:csv].any?
  end

  test "is valid with default status and attached csv" do
    import = Subscribers::Import.new(team: @team)
    import.csv.attach(io: StringIO.new("email\nfoo@example.com\n"), filename: "x.csv")
    assert import.valid?, import.errors.full_messages.join(", ")
    assert_equal "pending", import.status
  end

  test "predicate methods reflect status" do
    import = Subscribers::Import.new(team: @team)
    import.status = "processing"
    assert import.processing?
    assert_not import.completed?
  end
end
