require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  test "belongs to team and requires a name" do
    company = Company.new(team: @team)
    refute company.valid?
    assert_includes company.errors[:name], "can't be blank"

    company.name = "Destination DC"
    assert company.valid?, company.errors.full_messages.to_sentence
  end

  test "custom_attributes defaults to an empty hash" do
    company = @team.companies.create!(name: "Acme")
    assert_equal({}, company.custom_attributes)
  end

  test "team_id + intercom_id uniqueness is enforced at the DB layer" do
    @team.companies.create!(name: "Acme", intercom_id: "abc123")

    err = assert_raises(ActiveRecord::RecordNotUnique) do
      @team.companies.create!(name: "Acme 2", intercom_id: "abc123")
    end
    assert_match(/intercom_id/, err.message)
  end

  test "team_id + external_id uniqueness is enforced at the DB layer" do
    @team.companies.create!(name: "Acme", external_id: "tenant-1")

    err = assert_raises(ActiveRecord::RecordNotUnique) do
      @team.companies.create!(name: "Acme 2", external_id: "tenant-1")
    end
    assert_match(/external_id/, err.message)
  end

  test "a different team can reuse the same intercom_id" do
    other_team = create(:team)
    @team.companies.create!(name: "Acme", intercom_id: "abc123")
    assert_nothing_raised do
      other_team.companies.create!(name: "Other", intercom_id: "abc123")
    end
  end

  test "destroying a team destroys its companies" do
    @team.companies.create!(name: "Acme")
    assert_difference -> { Company.count }, -1 do
      @team.destroy!
    end
  end

  test "nullifies subscriber.company_id when company is destroyed" do
    company = @team.companies.create!(name: "Acme")
    sub = @team.subscribers.create!(email: "a@b.com", company: company)

    company.destroy!
    assert_nil sub.reload.company_id
  end
end
