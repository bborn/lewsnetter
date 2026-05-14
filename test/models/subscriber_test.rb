require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  test "company is optional" do
    sub = @team.subscribers.create!(email: "a@b.com")
    assert_nil sub.company
    assert sub.valid?
  end

  test "can associate a subscriber with a company on the same team" do
    company = @team.companies.create!(name: "Destination DC", intercom_id: "co-1")
    sub = @team.subscribers.create!(email: "lauren@destdc.com", company: company)
    assert_equal company, sub.reload.company
    assert_includes company.subscribers, sub
  end
end
