# Sequences: automated multi-step flows (the Intercom Series replacement).
# Hand-rolled like SuppressionsController rather than BulletTrain-scaffolded:
# Sequence isn't in roles.yml, so access piggy-backs on Team#manage (admins).
#
# The whole surface 404s unless the team has sequences_enabled.
class Account::SequencesController < Account::ApplicationController
  before_action :load_team_and_sequence
  before_action :authorize_team_access
  before_action :require_sequences_enabled

  # GET /account/teams/:team_id/sequences
  def index
    @sequences = @team.sequences.includes(:steps, :trigger_segment).order(updated_at: :desc)
    @enrollment_counts = SequenceEnrollment.where(sequence_id: @sequences.map(&:id))
      .group(:sequence_id, :state).count
  end

  # GET /account/sequences/:id
  def show
    @step_stats = @sequence.step_stats
    @enrollment_counts = @sequence.enrollment_counts
    @exit_reasons = @sequence.enrollments.where(state: %w[exited suppressed]).group(:exit_reason).count
  end

  # GET /account/teams/:team_id/sequences/new
  def new
    @sequence = @team.sequences.new(trigger_type: "event", status: "draft")
  end

  # GET /account/sequences/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/sequences
  def create
    @sequence = @team.sequences.new(sequence_params)
    if @sequence.save
      redirect_to account_sequence_path(@sequence), notice: "Sequence created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH /account/sequences/:id
  def update
    if @sequence.update(sequence_params)
      redirect_to account_sequence_path(@sequence), notice: "Sequence updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /account/sequences/:id
  def destroy
    @sequence.destroy
    redirect_to account_team_sequences_path(@team), notice: "Sequence deleted."
  end

  private

  # Shallow routes: member actions get :id, collection actions :team_id.
  # Both lookups go through the user's own teams so a guessed id from
  # another tenant raises RecordNotFound.
  def load_team_and_sequence
    if params[:id].present?
      @sequence = Sequence.where(team: current_user.teams).find(params[:id])
      @team = @sequence.team
    else
      @team = current_user.teams.find(params[:team_id])
    end
  end

  def authorize_team_access
    authorize! :manage, @team
  end

  def require_sequences_enabled
    raise ActionController::RoutingError, "Not Found" unless @team.sequences_enabled?
  end

  def sequence_params
    permitted = params.require(:sequence).permit(
      :name, :status, :trigger_type, :trigger_event_name, :trigger_segment_id,
      :exit_segment_id, :reentry_days, :sender_address_id
    )
    permitted[:reentry_days] = nil if permitted[:reentry_days].blank?
    permitted
  end
end
