class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :team
  belongs_to :user

  validates :team_id, presence: true
  validates :user_id, presence: true

  # `messages` is provided by acts_as_chat (has_many :messages, ordered by
  # created_at). Use the first user message's content as a human label.
  def derived_title
    title.presence ||
      messages.where(role: "user").first&.content&.truncate(60).presence ||
      "New conversation"
  end
end
