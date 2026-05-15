module StatusPillHelper
  # Renders a colored badge for a status string.
  #
  #   status_pill("draft")              # => <span class="badge badge-neutral">draft</span>
  #   status_pill("sent", label: "Sent on Mar 12")
  #
  # Used by:
  #   - Campaign show + index (draft/scheduled/sending/sent/failed)
  #   - Sender address show + index (verified/pending/not_in_ses/failed)
  #
  # Unknown statuses fall back to the neutral color. Label defaults to the
  # status humanized.
  STATUS_COLORS = {
    # Campaign statuses
    "draft" => "neutral",
    "scheduled" => "info",
    "sending" => "warn",
    "sent" => "success",
    "failed" => "error",
    # Sender address SES statuses (reused via this helper by the
    # sender_addresses implementer).
    "verified" => "success",
    "domain_verified" => "success",
    "success" => "success",
    "pending" => "warn",
    "temporary_failure" => "warn",
    "not_started" => "neutral",
    "not_in_ses" => "neutral",
    "unconfigured" => "neutral",
    "unknown" => "neutral",
    "error" => "error",
    "verification_failed" => "error"
  }.freeze

  # Humane labels for SES-derived sender_address.ses_status values. The
  # Sender Addresses index column maps the enum-leaky raw value through this
  # table to phrasing a non-engineer would actually read.
  SENDER_ADDRESS_STATUS_LABELS = {
    "verified" => "Verified",
    "success" => "Verified",
    "domain_verified" => "Verified (via domain)",
    "pending" => "Pending verification",
    "temporary_failure" => "Temporary failure — re-check soon",
    "not_started" => "Not yet checked",
    "not_in_ses" => "Not added to SES",
    "error" => "Verification error",
    "verification_failed" => "Verification failed",
    "failed" => "Verification failed",
    "unconfigured" => "SES not configured",
    "unknown" => "Unknown"
  }.freeze

  def status_pill(status, label: nil)
    status_str = status.to_s
    color = STATUS_COLORS[status_str] || "neutral"
    display = label || status_str.humanize
    content_tag(:span, display, class: "badge badge-#{color}")
  end

  # Convenience: render a status pill for a SenderAddress using the humane
  # ses_status labels. Falls back to "Unknown" when the column is blank.
  def sender_address_status_pill(sender_address)
    raw = sender_address.ses_status.to_s
    raw = "unknown" if raw.blank?
    label = SENDER_ADDRESS_STATUS_LABELS.fetch(raw, raw.humanize)
    status_pill(raw, label: label)
  end

  # Render a subscription-state pill for a Subscriber. Three states:
  #   subscribed (and never bounced)   → green   "Subscribed"
  #   subscribed=false (opted out)     → neutral "Unsubscribed"
  #   bounced_at set                   → rose    "Bounced"
  # Used in the subscribers index row and the subscriber show "Subscribed"
  # attribute, replacing the bare "Yes/No" rendering.
  def subscribed_pill(subscriber)
    if subscriber.bounced_at.present?
      status_pill("failed", label: "Bounced")
    elsif subscriber.subscribed
      status_pill("success", label: "Subscribed")
    else
      status_pill("draft", label: "Unsubscribed")
    end
  end
end
