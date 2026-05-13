require "test_helper"

class StatusPillHelperTest < ActionView::TestCase
  include StatusPillHelper

  test "renders a span with the color class for a known status" do
    html = status_pill("draft")
    assert_match %r{<span[^>]*class="badge badge-neutral"[^>]*>Draft</span>}, html

    assert_match(/badge-info/, status_pill("scheduled"))
    assert_match(/badge-warn/, status_pill("sending"))
    assert_match(/badge-success/, status_pill("sent"))
    assert_match(/badge-error/, status_pill("failed"))
  end

  test "falls back to badge-neutral for unknown status" do
    html = status_pill("zorp")
    assert_match(/badge-neutral/, html)
    assert_match(/Zorp/, html)
  end

  test "honors a custom label" do
    html = status_pill("sent", label: "Sent on Mar 12")
    assert_match(/badge-success/, html)
    assert_match(/Sent on Mar 12/, html)
  end

  test "accepts symbol status" do
    html = status_pill(:scheduled)
    assert_match(/badge-info/, html)
  end

  test "sender_address_status_pill maps not_in_ses to a humane label" do
    sa = OpenStruct.new(ses_status: "not_in_ses")
    html = sender_address_status_pill(sa)
    assert_match(/Not added to SES/, html)
    assert_match(/badge-neutral/, html)
  end

  test "sender_address_status_pill maps success to Verified / success color" do
    sa = OpenStruct.new(ses_status: "success")
    html = sender_address_status_pill(sa)
    assert_match(/Verified/, html)
    assert_match(/badge-success/, html)
  end

  test "sender_address_status_pill maps domain_verified to its own label" do
    sa = OpenStruct.new(ses_status: "domain_verified")
    html = sender_address_status_pill(sa)
    assert_match(/Verified \(via domain\)/, html)
    assert_match(/badge-success/, html)
  end

  test "sender_address_status_pill maps pending to Pending verification" do
    sa = OpenStruct.new(ses_status: "pending")
    html = sender_address_status_pill(sa)
    assert_match(/Pending verification/, html)
    assert_match(/badge-warn/, html)
  end

  test "sender_address_status_pill falls back to Unknown for blank status" do
    sa = OpenStruct.new(ses_status: "")
    html = sender_address_status_pill(sa)
    assert_match(/Unknown/, html)
  end
end
