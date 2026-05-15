class DropAgentConversationsAndMessages < ActiveRecord::Migration[8.1]
  # We're replacing the bespoke AgentConversation/AgentMessage models with
  # ruby_llm's Chat/Message/ToolCall/Model. Old tables are tiny (one seeded
  # conversation in prod) and have no production traffic yet — safe to drop.
  def change
    drop_table :agent_messages, if_exists: true do |t|
      t.references :agent_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.string :tool_name
      t.json :tool_arguments
      t.json :tool_result
      t.string :error_class
      t.text :error_message
      t.timestamps
      t.index [:agent_conversation_id, :created_at]
    end

    drop_table :agent_conversations, if_exists: true do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.timestamps
      t.index [:team_id, :user_id]
    end
  end
end
