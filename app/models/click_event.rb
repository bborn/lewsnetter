# One row per hit on the click-tracking redirect (or the hidden honeypot
# link). Written by Tracking::ClicksController via `.record!`, which also
# classifies the hit as human or automated. Campaign#delivery_stats and
# Campaign#top_links read human numbers from here; the Delivery columns
# (clicked_at / click_count / last_clicked_url) stay as raw counters.
#
# Classification rules, in order (first match wins; see MachineTraffic for
# the thresholds):
#
#   honeypot            the hidden link CampaignRenderer adds to every email
#   head_request        HEAD instead of GET (link checkers, never a browser)
#   blank_user_agent    no User-Agent header
#   scanner_user_agent  UA matches MachineTraffic::CLICK_SCANNER_PATTERN
#   too_fast            within CLICK_SEND_PROXIMITY_WINDOW of delivery
#   honeypot_burst      the delivery's honeypot was hit within
#                       HONEYPOT_BURST_WINDOW of this click
#   link_fanout         FANOUT_MIN_DISTINCT_LINKS distinct links hit on this
#                       delivery within FANOUT_WINDOW
#
# The last two also reach back: a honeypot hit flags the delivery's other
# clicks inside the burst window, and a fan-out flags the earlier clicks in
# its window. Clicks outside those windows are left alone, so a person who
# clicks after the scanner pass still counts.
class ClickEvent < ApplicationRecord
  belongs_to :delivery

  REASONS = %w[
    honeypot head_request blank_user_agent scanner_user_agent too_fast
    honeypot_burst link_fanout
  ].freeze

  scope :human, -> { where(automated: false) }
  scope :automated, -> { where(automated: true) }
  scope :links, -> { where(honeypot: false) }

  validates :clicked_at, presence: true
  validates :automated_reason, inclusion: {in: REASONS}, allow_nil: true

  # Records + classifies one hit. Returns the saved event, or nil when the
  # delivery is already at MachineTraffic::MAX_EVENTS_PER_DELIVERY.
  def self.record!(delivery:, url:, user_agent:, ip:, http_method:, honeypot: false, at: Time.current)
    return nil if where(delivery_id: delivery.id).count >= MachineTraffic::MAX_EVENTS_PER_DELIVERY

    event = new(
      delivery: delivery,
      url: url.presence && url.to_s[0, 2048],
      clicked_at: at,
      user_agent: MachineTraffic.truncate_user_agent(user_agent),
      ip_prefix: MachineTraffic.ip_prefix(ip),
      http_method: http_method.to_s.upcase.presence,
      honeypot: honeypot
    )
    event.automated_reason = event.classify
    event.automated = event.automated_reason.present?
    event.save!
    event.flag_burst!
    event
  end

  # Returns the automated reason, or nil for a human click.
  def classify
    return "honeypot" if honeypot?
    return "head_request" if http_method == "HEAD"
    return "blank_user_agent" if user_agent.blank?
    return "scanner_user_agent" if MachineTraffic::CLICK_SCANNER_PATTERN.match?(user_agent)
    return "too_fast" if MachineTraffic.within_send_window?(delivery, clicked_at, MachineTraffic::CLICK_SEND_PROXIMITY_WINDOW)
    return "honeypot_burst" if honeypot_hit_nearby?
    return "link_fanout" if fanout?
    nil
  end

  # Retroactively flags sibling clicks that belong to the same machine burst.
  def flag_burst!
    if honeypot?
      window = MachineTraffic::HONEYPOT_BURST_WINDOW
      siblings.human
        .where(clicked_at: (clicked_at - window)..(clicked_at + window))
        .update_all(automated: true, automated_reason: "honeypot_burst", updated_at: Time.current)
    elsif automated_reason == "link_fanout"
      siblings.human.links
        .where(clicked_at: (clicked_at - MachineTraffic::FANOUT_WINDOW)..clicked_at)
        .update_all(automated: true, automated_reason: "link_fanout", updated_at: Time.current)
    end
  end

  private

  def siblings
    self.class.where(delivery_id: delivery_id).where.not(id: id)
  end

  def honeypot_hit_nearby?
    window = MachineTraffic::HONEYPOT_BURST_WINDOW
    self.class.where(delivery_id: delivery_id, honeypot: true)
      .where(clicked_at: (clicked_at - window)..(clicked_at + window))
      .exists?
  end

  def fanout?
    return false if url.blank?
    recent = self.class.links
      .where(delivery_id: delivery_id)
      .where(clicked_at: (clicked_at - MachineTraffic::FANOUT_WINDOW)..clicked_at)
      .distinct
      .pluck(:url)
    (recent | [url]).compact.size >= MachineTraffic::FANOUT_MIN_DISTINCT_LINKS
  end
end
