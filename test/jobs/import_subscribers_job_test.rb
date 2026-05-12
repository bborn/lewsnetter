require "test_helper"

class ImportSubscribersJobTest < ActiveJob::TestCase
  setup do
    @team = create(:team)
    @import = Subscribers::Import.new(team: @team)
    @import.csv.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_subscribers.csv")),
      filename: "sample_subscribers.csv",
      content_type: "text/csv"
    )
    @import.save!
  end

  test "imports valid rows and reports per-row errors" do
    assert_difference "@team.subscribers.count", 8 do
      ImportSubscribersJob.perform_now(@import.id)
    end

    @import.reload
    assert_equal "completed", @import.status
    assert_equal 10, @import.processed
    assert_equal 10, @import.total_rows
    assert_equal 8, @import.created_count
    assert_equal 1, @import.updated_count, "ext-001 should be matched + updated"
    assert_equal 1, @import.error_count, "row with no external_id and no email should error"
    assert_not_nil @import.started_at
    assert_not_nil @import.finished_at
    assert @import.errors_log.is_a?(Array)
    assert_equal 1, @import.errors_log.size
  end

  test "upsert by external_id updates existing subscriber" do
    @team.subscribers.create!(external_id: "ext-001", email: "old@example.com", name: "Old Name")

    ImportSubscribersJob.perform_now(@import.id)

    sub = @team.subscribers.find_by(external_id: "ext-001")
    # The CSV has ext-001 twice; the second occurrence with alice-renamed@example.com
    # should be the final state.
    assert_equal "alice-renamed@example.com", sub.email
    assert_equal "Alice Renamed", sub.name
  end

  test "folds unknown columns into custom_attributes" do
    ImportSubscribersJob.perform_now(@import.id)

    alice = @team.subscribers.find_by(email: "alice-renamed@example.com")
    assert_equal "growth", alice.custom_attributes["plan"]
    assert_equal "Acme Corp", alice.custom_attributes["company"]
  end

  test "parses subscribed booleans across true/false/yes/no" do
    ImportSubscribersJob.perform_now(@import.id)

    assert_equal true, @team.subscribers.find_by(external_id: "ext-006").subscribed
    assert_equal false, @team.subscribers.find_by(external_id: "ext-008").subscribed
    assert_equal false, @team.subscribers.find_by(external_id: "ext-003").subscribed
  end

  test "marks import as failed and re-raises if csv attachment is missing" do
    import = Subscribers::Import.create!(team: @team, csv: nil) rescue nil
    # Validation prevents missing csv on create; simulate a record whose blob
    # vanished out from under it.
    import = Subscribers::Import.new(team: @team)
    import.csv.attach(io: StringIO.new("email\n"), filename: "x.csv")
    import.save!
    import.csv.purge

    ImportSubscribersJob.perform_now(import.id)
    import.reload
    assert_equal "failed", import.status
    assert_match(/No CSV attachment/, import.notes.to_s)
  end
end
