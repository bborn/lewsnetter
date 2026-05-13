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
end
