class AgentConversation < ApplicationRecord
  belongs_to :team
  belongs_to :user
  has_many :agent_messages, -> { order(:created_at) }, dependent: :destroy

  validates :team_id, presence: true
  validates :user_id, presence: true

  def message_count
    agent_messages.size
  end

  def derived_title
    title.presence || agent_messages.where(role: "user").first&.content&.truncate(60).presence || "New conversation"
  end
end
