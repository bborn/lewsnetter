require "test_helper"

class SubscriberEmailDomainTest < ActiveSupport::TestCase
  setup { @team = create(:team) }

  test "derives email_domain from the address on create (downcased)" do
    s = @team.subscribers.create!(email: "Jane@Brand.com", name: "Jane", subscribed: true)
    assert_equal "brand.com", s.email_domain
  end

  test "recomputes email_domain when the email changes" do
    s = @team.subscribers.create!(email: "a@old.com", subscribed: true)
    s.update!(email: "a@new.io")
    assert_equal "new.io", s.email_domain
  end

  test "domain segments are queryable on the plaintext column" do
    @team.subscribers.create!(email: "x@acme.com", subscribed: true)
    @team.subscribers.create!(email: "y@acme.com", subscribed: true)
    @team.subscribers.create!(email: "z@other.com", subscribed: true)
    assert_equal 2, @team.subscribers.where(email_domain: "acme.com").count
  end

  test "an address with no @ leaves email_domain nil" do
    s = @team.subscribers.create!(email: "weird", subscribed: true)
    assert_nil s.email_domain
  end
end
