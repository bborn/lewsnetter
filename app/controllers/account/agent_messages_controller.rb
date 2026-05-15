class Account::AgentMessagesController < Account::ApplicationController
  before_action :load_conversation

  def create
    Agent::Runner.new(conversation: @agent_conversation).handle_user_message(params[:content].to_s)
    respond_to do |format|
      format.html { redirect_to [:account, @agent_conversation] }
      format.json { render json: {ok: true} }
    end
  end

  private

  def load_conversation
    @agent_conversation = current_team.agent_conversations.where(user_id: current_user.id).find(params[:agent_conversation_id])
  end
end
