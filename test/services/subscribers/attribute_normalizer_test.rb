require "test_helper"

module Subscribers
  class AttributeNormalizerTest < ActiveSupport::TestCase
    test "converts CSV string to array for list-like keys" do
      out = AttributeNormalizer.call(
        "tabs_enabled" => "billing,brand_account,influencer_hub",
        "company_tabs_enabled" => "a,b,c"
      )
      assert_equal %w[billing brand_account influencer_hub], out["tabs_enabled"]
      assert_equal %w[a b c], out["company_tabs_enabled"]
    end

    test "passes arrays through unchanged for list-like keys" do
      out = AttributeNormalizer.call("tabs_enabled" => %w[billing reports])
      assert_equal %w[billing reports], out["tabs_enabled"]
    end

    test "leaves non-list-like keys alone even if they look CSV-shaped" do
      # A real "company_name" like "Acme, Inc." shouldn't get split.
      out = AttributeNormalizer.call("company_name" => "Acme, Inc.")
      assert_equal "Acme, Inc.", out["company_name"]
    end

    test "leaves CSV-shaped values alone when surrounded by whitespace" do
      # "Hello, world" → not a list, has spaces around the comma.
      out = AttributeNormalizer.call("topic_tags" => "Hello, world")
      assert_equal "Hello, world", out["topic_tags"]
    end

    test "splits when key matches a known list-like suffix" do
      out = AttributeNormalizer.call(
        "subdomain_ids" => "1,2,3",
        "topic_tags" => "travel,food,family",
        "company_tabs" => "a,b"
      )
      assert_equal %w[1 2 3],            out["subdomain_ids"]
      assert_equal %w[travel food family], out["topic_tags"]
      assert_equal %w[a b],              out["company_tabs"]
    end

    test "handles empty / nil input gracefully" do
      assert_equal({}, AttributeNormalizer.call(nil))
      assert_equal({}, AttributeNormalizer.call({}))
    end

    test "preserves order and other keys" do
      out = AttributeNormalizer.call(
        "email"  => "a@x.com",
        "tabs_enabled" => "x,y",
        "plan"   => "growth"
      )
      assert_equal %w[email tabs_enabled plan], out.keys
      assert_equal %w[x y], out["tabs_enabled"]
    end
  end
end
