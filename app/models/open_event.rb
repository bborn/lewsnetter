# One row per open-pixel fetch. Written by Tracking::OpensController via
# `.record!`, which classifies the fetch as human or automated.
# Delivery#opened_at stays as the raw "first pixel fetch" stamp.
#
# Classification rules, in order (first match wins; see MachineTraffic):
#
#   head_request        HEAD instead of GET
#   blank_user_agent    no User-Agent header
#   apple_mpp           Apple Mail Privacy Protection proxy (bare
#                       "Mozilla/5.0" UA). Apple prefetches every image on
#                       delivery, so these say nothing about reading.
#   scanner_user_agent  UA matches MachineTraffic::OPEN_SCANNER_PATTERN
#   too_fast            within OPEN_SEND_PROXIMITY_WINDOW of delivery
#
# Trade-off worth knowing: flagging Apple MPP means real Apple Mail readers
# who never click are invisible in the human open count. That's the honest
# reading — MPP makes their opens unknowable — and Campaign#delivery_stats
# counts any recipient with a human click as opened, which recovers the
# Apple Mail readers who acted on the email.
class OpenEvent < ApplicationRecord
  belongs_to :delivery

  REASONS = %w[head_request blank_user_agent apple_mpp scanner_user_agent too_fast].freeze

  scope :human, -> { where(automated: false) }
  scope :automated, -> { where(automated: true) }

  validates :opened_at, presence: true
  validates :automated_reason, inclusion: {in: REASONS}, allow_nil: true

  # Records + classifies one pixel fetch. Returns the saved event, or nil
  # when the delivery is already at MachineTraffic::MAX_EVENTS_PER_DELIVERY.
  def self.record!(delivery:, user_agent:, ip:, http_method:, at: Time.current)
    return nil if where(delivery_id: delivery.id).count >= MachineTraffic::MAX_EVENTS_PER_DELIVERY

    event = new(
      delivery: delivery,
      opened_at: at,
      user_agent: MachineTraffic.truncate_user_agent(user_agent),
      ip_prefix: MachineTraffic.ip_prefix(ip),
      http_method: http_method.to_s.upcase.presence
    )
    event.automated_reason = event.classify
    event.automated = event.automated_reason.present?
    event.save!
    event
  end

  # Returns the automated reason, or nil for a human open.
  def classify
    return "head_request" if http_method == "HEAD"
    return "blank_user_agent" if user_agent.blank?
    return "apple_mpp" if user_agent == MachineTraffic::APPLE_MPP_USER_AGENT
    return "scanner_user_agent" if MachineTraffic::OPEN_SCANNER_PATTERN.match?(user_agent)
    return "too_fast" if MachineTraffic.within_send_window?(delivery, opened_at, MachineTraffic::OPEN_SEND_PROXIMITY_WINDOW)
    nil
  end
end
