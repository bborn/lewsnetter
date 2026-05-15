class Account::AgentConversationsController < Account::ApplicationController
  account_load_and_authorize_resource :agent_conversation, through: :team, through_association: :agent_conversations

  def index
    @agent_conversations = current_team.agent_conversations.where(user_id: current_user.id).order(updated_at: :desc)
  end

  def show
    @messages = @agent_conversation.agent_messages
  end

  def create
    @agent_conversation.user = current_user
    if @agent_conversation.save
      starter = params[:starter_prompt].to_s.strip
      if starter.present?
        Agent::Runner.new(conversation: @agent_conversation).handle_user_message(starter)
      end
      redirect_to [:account, @agent_conversation]
    else
      redirect_to [:account, current_team, :agent_conversations], alert: "Could not start conversation"
    end
  end

  def destroy
    @agent_conversation.destroy
    redirect_to [:account, :agent_conversations], notice: "Conversation deleted"
  end
end
