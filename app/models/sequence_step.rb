# One email in a Sequence. The step's own columns (subject, preheader, body,
# template) are the source of truth; after every save they are copied onto a
# hidden backing Campaign (status "sequence") that SesSender sends from, so
# Deliveries, SES webhooks, open/click tracking, unsubscribe links and
# Campaign#delivery_stats all work for sequence emails unchanged.
class SequenceStep < ApplicationRecord
  # 🚅 add concerns above.

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
  after_save :sync_backing_campaign
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

  # 🚅 add methods above.

  private

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
