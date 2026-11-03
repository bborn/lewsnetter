class Event < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :subscriber
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :named, ->(name) { where(name: name) }
  scope :since, ->(time) { where("occurred_at >= ?", time) }
  # 🚅 add scopes above.

  validates :name, presence: true
  validates :occurred_at, presence: true
  # 🚅 add validations above.

  after_create_commit :enqueue_sequence_enrollment
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.

  private

  # Event-triggered sequences. Cheap gate here (flag + recency) so teams
  # without Sequences never enqueue anything; EnrollOnEventJob does the rest.
  def enqueue_sequence_enrollment
    return unless team.sequences_enabled?
    return if occurred_at < Sequence::EVENT_ENROLLMENT_WINDOW.ago
    EnrollOnEventJob.perform_later(id)
  end
end
