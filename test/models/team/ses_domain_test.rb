require "test_helper"

class Team::SesDomainTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
  end

  test "valid with a simple hostname" do
    domain = @team.build_ses_domain(domain: "hey.example.com")
    assert domain.valid?, domain.errors.full_messages.to_sentence
  end

  test "valid with a root domain" do
    assert @team.build_ses_domain(domain: "example.com").valid?
  end

  test "lowercases and strips whitespace before validation" do
    domain = @team.build_ses_domain(domain: "  Hey.Example.com  ")
    assert domain.valid?
    assert_equal "hey.example.com", domain.domain
  end

  test "strips an accidentally-pasted https:// prefix" do
    domain = @team.build_ses_domain(domain: "https://hey.example.com/")
    assert domain.valid?
    assert_equal "hey.example.com", domain.domain
  end

  test "strips a leading @ if the user pastes an email-style value" do
    domain = @team.build_ses_domain(domain: "@hey.example.com")
    assert domain.valid?
    assert_equal "hey.example.com", domain.domain
  end

  test "rejects a domain with no dot" do
    domain = @team.build_ses_domain(domain: "localhost")
    refute domain.valid?
    assert_includes domain.errors[:domain].to_sentence.downcase, "hostname"
  end

  test "rejects a domain with whitespace" do
    refute @team.build_ses_domain(domain: "hey example.com").valid?
  end

  test "rejects an empty domain" do
    domain = @team.build_ses_domain(domain: "")
    refute domain.valid?
    assert_includes domain.errors[:domain].to_sentence.downcase, "blank"
  end

  test "rejects a duplicate domain on the same team" do
    @team.create_ses_domain!(domain: "hey.example.com")
    # Bypass has_one's auto-replace by building a fresh row directly on the
    # class (has_one would otherwise delete the previous before saving).
    dup = Team::SesDomain.new(team: @team, domain: "hey.example.com")
    refute dup.valid?
    assert_includes dup.errors[:domain].to_sentence.downcase, "taken"
  end

  test "dkim_token_list parses the JSON-encoded column" do
    domain = @team.build_ses_domain(domain: "hey.example.com")
    domain.dkim_tokens = JSON.dump(%w[abc def ghi])
    assert_equal %w[abc def ghi], domain.dkim_token_list
  end

  test "dkim_token_list returns [] for blank or invalid JSON" do
    domain = @team.build_ses_domain(domain: "hey.example.com")
    assert_equal [], domain.dkim_token_list
    domain.dkim_tokens = "not json"
    assert_equal [], domain.dkim_token_list
  end

  test "dkim_token_list= encodes an array" do
    domain = @team.build_ses_domain(domain: "hey.example.com")
    domain.dkim_token_list = %w[abc def ghi]
    assert_equal %w[abc def ghi], JSON.parse(domain.dkim_tokens)
  end

  test "cname_records builds the three CNAMEs from the tokens" do
    domain = @team.build_ses_domain(domain: "hey.example.com")
    domain.dkim_token_list = %w[tokenone tokentwo tokenthree]
    records = domain.cname_records
    assert_equal 3, records.size
    assert_equal({host: "tokenone._domainkey.hey.example.com",
                  value: "tokenone.dkim.amazonses.com",
                  type: "CNAME"}, records.first)
    assert_equal "CNAME", records.last[:type]
  end

  test "cname_records is empty when no tokens are stored yet" do
    assert_equal [], @team.build_ses_domain(domain: "hey.example.com").cname_records
  end

  test "status predicates" do
    domain = @team.build_ses_domain(domain: "hey.example.com")
    assert domain.unverified?
    domain.status = "pending"
    assert domain.pending?
    domain.status = "verified"
    assert domain.verified?
    domain.status = "failed"
    assert domain.failed?
  end
end
