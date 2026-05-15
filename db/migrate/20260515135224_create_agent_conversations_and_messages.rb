class CreateAgentConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_conversations do |t|
      t.references :team, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :title, null: true   # optional human label, derived later
      t.timestamps
    end
    add_index :agent_conversations, [:team_id, :user_id]

    create_table :agent_messages do |t|
      t.references :agent_conversation, null: false, foreign_key: true, index: true
      t.string :role, null: false   # user | assistant | tool_call | tool_result | error
      t.text :content                # the markdown body for user/assistant messages
      t.string :tool_name            # for role=tool_call|tool_result
      t.json :tool_arguments         # for role=tool_call
      t.json :tool_result            # for role=tool_result
      t.string :error_class          # for role=error
      t.text :error_message          # for role=error
      t.timestamps
    end
    add_index :agent_messages, [:agent_conversation_id, :created_at]
  end
end
