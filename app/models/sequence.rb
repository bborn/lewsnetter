# An automated, multi-step email flow. Subscribers are enrolled by a tracked
# event (trigger_type "event") or by entering a segment (trigger_type
# "segment", picked up by SegmentEnrollmentSweepJob), then walked through the
# steps in position order. Each step waits `delay_minutes` after the previous
# one.
#
# Gated per team by `teams.sequences_enabled`. With the flag off nothing
# enrolls and nothing sends, whatever the sequence's own status.
class Sequence < ApplicationRecord
  # 🚅 add concerns above.

  STATUSES = %w[draft active paused].freeze
  TRIGGER_TYPES = %w[event segment].freeze

  # Events older than this don't enroll anyone. Stops a historical backfill
  # through /events/track (or /events/bulk) from firing welcome emails for
  # things that happened months ago.
  EVENT_ENROLLMENT_WINDOW = 24.hours

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :trigger_segment, class_name: "Segment", optional: true
  belongs_to :exit_segment, class_name: "Segment", optional: true
  belongs_to :sender_address, optional: true
  # 🚅 add belongs_to associations above.

  has_many :steps, -> { order(:position, :id) }, class_name: "SequenceStep",
    dependent: :destroy, inverse_of: :sequence
  has_many :enrollments, class_name: "SequenceEnrollment", dependent: :delete_all
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :active, -> { where(status: "active") }
  scope :event_triggered, ->(name) { where(trigger_type: "event", trigger_event_name: name) }
  scope :segment_triggered, -> { where(trigger_type: "segment") }
  # 🚅 add scopes above.

  validates :name, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :trigger_type, inclusion: {in: TRIGGER_TYPES}
  validates :trigger_event_name, presence: true, if: -> { trigger_type == "event" }
  validates :trigger_segment, presence: true, if: -> { trigger_type == "segment" }
  validates :reentry_days, numericality: {only_integer: true, greater_than: 0}, allow_nil: true
  validates :trigger_segment, scope: true
  validates :exit_segment, scope: true
  validates :sender_address, scope: true
  validate :sender_address_required_to_activate
  # 🚅 add validations above.

  after_update :sync_step_senders, if: :saved_change_to_sender_address_id?
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  def valid_trigger_segments = team.segments
  def valid_exit_segments = team.segments
  def valid_sender_addresses = team.sender_addresses

  def live?
    active? && team.sequences_enabled?
  end

  # Enrolls the subscriber if every rule allows it. Returns the new
  # SequenceEnrollment, or nil when the subscriber is turned away. Safe to
  # call repeatedly and concurrently: the partial unique index on active
  # enrollments makes the second insert a no-op.
  def enroll!(subscriber, at: Time.current)
    return nil unless enrollable?(subscriber, at: at)

    first = steps.first
    enrollments.create!(
      subscriber: subscriber,
      current_step: 0,
      next_send_at: at + first.delay_minutes.minutes,
      state: "active",
      enrolled_at: at
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def enrollable?(subscriber, at: Time.current)
    return false unless live?
    return false unless subscriber.team_id == team_id
    # Not `subscribed?`: Mailkick redefines it as subscribed?(list).
    return false unless subscriber[:subscribed]
    return false if steps.empty?
    return false if enrollments.where(subscriber: subscriber, state: "active").exists?
    return false unless reentry_allowed?(subscriber, at: at)
    return false if Suppression.for_team_emails(team, [subscriber.email.to_s.downcase]).any?
    return false if exit_segment && subscriber_in_segment?(exit_segment, subscriber)
    true
  end

  # nil reentry_days = once ever. Otherwise the previous enrollment must
  # have started at least reentry_days ago.
  def reentry_allowed?(subscriber, at: Time.current)
    last = enrollments.where(subscriber: subscriber).maximum(:enrolled_at)
    return true if last.nil?
    return false if reentry_days.nil?
    last <= at - reentry_days.days
  end

  # Does the segment match this one subscriber? An invalid predicate counts
  # as "no match" so a broken segment can't block a whole sequence.
  def subscriber_in_segment?(segment, subscriber)
    segment.applies_to(team.subscribers.where(id: subscriber.id)).exists?
  rescue Segment::InvalidPredicate => e
    Rails.logger.warn("[Sequence #{id}] segment #{segment.id} invalid: #{e.message}")
    false
  end

  def enrollment_counts
    enrollments.group(:state).count.reverse_merge(
      "active" => 0, "completed" => 0, "exited" => 0, "suppressed" => 0
    )
  end

  # Per-step funnel: sends and engagement from the step's deliveries,
  # `waiting` = active enrollments whose next step is this one.
  def step_stats
    waiting = enrollments.where(state: "active").group(:current_step).count
    steps.each_with_index.map do |step, index|
      stats = step.delivery_stats
      {
        step: step,
        position: index + 1,
        waiting: waiting.fetch(index, 0),
        skipped: step.skipped_count,
        sent: stats[:sent],
        delivered: stats[:delivered],
        opened: stats[:opened],
        clicked: stats[:clicked],
        bounced: stats[:bounced],
        unsubscribed: stats[:unsubscribed]
      }
    end
  end

  # 🚅 add methods above.

  private

  def sync_step_senders
    steps.includes(:campaign).each { |step| step.campaign&.update!(sender_address: sender_address) }
  end

  def sender_address_required_to_activate
    return unless active?
    errors.add(:sender_address, "is required to activate a sequence") if sender_address.nil?
  end
end
