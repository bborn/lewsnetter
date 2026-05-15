class Account::ChatsController < Account::ApplicationController
  account_load_and_authorize_resource :chat, through: :team, through_association: :chats

  def index
    @chats = current_team.chats.where(user_id: current_user.id).order(updated_at: :desc)
  end

  def show
    @messages = @chat.messages
  end

  def create
    @chat.user = current_user
    if @chat.save
      starter = params[:starter_prompt].to_s.strip
      if starter.present?
        @chat.messages.create!(role: "user", content: starter)
        # Best-effort: enqueue a background reply. For v1, nudge the user to
        # the show page where the Cable subscription will run the next turn
        # when they hit Send. Avoids blocking create on an LLM round-trip.
      end
      redirect_to [:account, @chat]
    else
      redirect_to [:account, current_team, :chats], alert: "Could not start chat"
    end
  end

  def destroy
    @chat.destroy
    redirect_to [:account, current_team, :chats], notice: "Chat deleted"
  end
end
