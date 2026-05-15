class AgentMessage < ApplicationRecord
  ROLES = %w[user assistant tool_call tool_result error].freeze

  belongs_to :agent_conversation

  validates :role, inclusion: {in: ROLES}
  validates :content, presence: true, if: -> { role.in?(%w[user assistant]) }
  validates :tool_name, presence: true, if: -> { role.in?(%w[tool_call tool_result]) }
end
