# The emails inside a Sequence. Same access rules as SequencesController:
# Team#manage plus the team's sequences_enabled flag.
class Account::SequenceStepsController < Account::ApplicationController
  before_action :load_sequence_and_step
  before_action :authorize_team_access
  before_action :require_sequences_enabled

  # GET /account/sequences/:sequence_id/steps/new
  def new
    @step = @sequence.steps.new(delay_minutes: @sequence.steps.any? ? 1440 : 0)
  end

  # GET /account/steps/:id/edit
  def edit
  end

  # POST /account/sequences/:sequence_id/steps
  def create
    @step = @sequence.steps.new(step_params)
    if @step.save
      redirect_to account_sequence_path(@sequence), notice: "Step added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH /account/steps/:id
  def update
    if @step.update(step_params)
      redirect_to account_sequence_path(@sequence), notice: "Step updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /account/steps/:id
  def destroy
    @step.destroy
    redirect_to account_sequence_path(@sequence), notice: "Step removed."
  end

  private

  def load_sequence_and_step
    teams = current_user.teams
    if params[:id].present?
      @step = SequenceStep.joins(:sequence).where(sequences: {team_id: teams}).find(params[:id])
      @sequence = @step.sequence
    else
      @sequence = Sequence.where(team: teams).find(params[:sequence_id])
    end
    @team = @sequence.team
  end

  def authorize_team_access
    authorize! :manage, @team
  end

  def require_sequences_enabled
    raise ActionController::RoutingError, "Not Found" unless @team.sequences_enabled?
  end

  def step_params
    permitted = params.require(:sequence_step).permit(
      :subject, :preheader, :body_markdown, :email_template_id, :skip_segment_id,
      :delay_amount, :delay_unit, :sent_tag, :action_trigger, :action_tag, :action_exit
    )
    permitted[:email_template_id] = nil if permitted[:email_template_id].blank?
    permitted[:skip_segment_id] = nil if permitted[:skip_segment_id].blank?
    permitted
  end
end
