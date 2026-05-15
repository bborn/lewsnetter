class AgentChannel < ApplicationCable::Channel
  def subscribed
    conversation = AgentConversation.find_by(id: params[:conversation_id])
    if conversation.nil? || conversation.user_id != current_user.id
      reject
      return
    end

    @conversation = conversation
    stream_for conversation
  end

  def send_message(data)
    return if @conversation.nil?
    Agent::Runner.new(
      conversation: @conversation,
      on_event: ->(event) { AgentChannel.broadcast_to(@conversation, event) }
    ).handle_user_message(data["content"].to_s)
  end
end
