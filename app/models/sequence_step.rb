# One email in a Sequence. The step's own columns (subject, preheader, body,
# template) are the source of truth; after every save they are copied onto a
# hidden backing Campaign (status "sequence") that SesSender sends from, so
# Deliveries, SES webhooks, open/click tracking, unsubscribe links and
# Campaign#delivery_stats all work for sequence emails unchanged.
class SequenceStep < ApplicationRecord
  # 🚅 add concerns above.

  # Form-facing delay: "wait 3 days" instead of 4320 minutes. Setting both
  # writes delay_minutes before validation.
  DELAY_UNITS = {"minutes" => 1, "hours" => 60, "days" => 1440}.freeze
  attr_writer :delay_amount, :delay_unit
  # 🚅 add attribute accessors above.

  belongs_to :sequence, inverse_of: :steps
  belongs_to :email_template, optional: true
  belongs_to :skip_segment, class_name: "Segment", optional: true
  belongs_to :campaign, optional: true, dependent: :destroy
  # 🚅 add belongs_to associations above.

  has_many :deliveries, dependent: :nullify
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :subject, presence: true
  validates :body_markdown, presence: true
  validates :delay_minutes, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :email_template, scope: true
  validates :skip_segment, scope: true
  # 🚅 add validations above.

  before_validation :assign_position, on: :create
  before_validation :apply_delay_amount
  after_save :sync_backing_campaign
  before_destroy :shift_later_enrollments
  # 🚅 add callbacks above.

  delegate :team, to: :sequence
  # 🚅 add delegations above.

  def valid_email_templates = team.email_templates
  def valid_skip_segments = team.segments

  # 0-based index within the sequence — what SequenceEnrollment#current_step
  # points at.
  def index
    sequence.steps.index(self)
  end

  def delivery_stats
    return Campaign.new.delivery_stats if campaign.nil?
    campaign.delivery_stats
  end

  # Largest unit that divides the delay evenly.
  def delay_unit
    return @delay_unit if DELAY_UNITS.key?(@delay_unit)
    minutes = delay_minutes.to_i
    return "minutes" if minutes.zero?
    DELAY_UNITS.keys.rfind { |unit| (minutes % DELAY_UNITS[unit]).zero? }
  end

  def delay_amount
    return @delay_amount if @delay_amount
    delay_minutes.to_i / DELAY_UNITS[delay_unit]
  end

  # 🚅 add methods above.

  private

  # Enrollments point at steps by 0-based index. Removing a step shifts the
  # later ones down by one, so pull the pointers of anyone past it back too
  # (anyone waiting on this step now waits on the next).
  def shift_later_enrollments
    removed = index
    return if removed.nil?
    SequenceEnrollment.where(sequence_id: sequence_id, state: "active")
      .where("current_step > ?", removed)
      .update_all("current_step = current_step - 1")
  end

  def apply_delay_amount
    return if @delay_amount.nil? || @delay_amount.to_s.strip.empty?
    unit = DELAY_UNITS.fetch(delay_unit, 1)
    self.delay_minutes = Integer(@delay_amount.to_s, exception: false)&.*(unit) || -1
  end

  def assign_position
    return if position.to_i > 0
    self.position = (sequence.steps.maximum(:position) || 0) + 1
  end

  def sync_backing_campaign
    attrs = {
      team: sequence.team,
      status: "sequence",
      subject: subject,
      preheader: preheader,
      body_markdown: body_markdown,
      email_template: email_template,
      # No template = a plain-text email (Campaign needs one or the other).
      plain_text_only: email_template.nil?,
      sender_address: sequence.sender_address
    }
    if campaign
      campaign.update!(attrs)
    else
      backing = Campaign.create!(attrs)
      update_column(:campaign_id, backing.id)
      association(:campaign).target = backing
    end
  end
end
