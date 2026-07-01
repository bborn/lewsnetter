class Account::SubscribersController < Account::ApplicationController
  account_load_and_authorize_resource :subscriber, through: :team, through_association: :subscribers,
    except: [:search]

  # GET /account/teams/:team_id/subscribers
  # GET /account/teams/:team_id/subscribers.json
  def index
    # Newest first — the list has an "Added" column, so recency is the natural
    # order. id is the tiebreaker so bulk-imported rows sharing a created_at
    # (same-second backfill) stay stably ordered across paginated pages.
    @subscribers = @subscribers.reorder(created_at: :desc, id: :desc)
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/subscribers/search.json?q=...
  #
  # Lightweight typeahead endpoint for the "Preview as" autocomplete on the
  # campaign show page. Matches against email / name / external_id, limited
  # to 10 hits. Not paginated — UI is a quick narrow-then-pick affordance.
  def search
    @team = current_user.teams.find(params[:team_id])
    authorize! :read, Subscriber.new(team: @team)

    q = params[:q].to_s.strip
    if q.blank?
      render json: []
      return
    end

    # W2 — email is deterministic-encrypted, so `LIKE` over the ciphertext
    # matches nothing (functional dead code). Mirror the working approach
    # from Mcp::Tools::Subscribers::List: exact-match email, substring-LIKE
    # for name + external_id, then merge the id sets. See audit W2.
    like = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
    scope = @team.subscribers
    exact_email_ids = scope.where(email: q).pluck(:id)
    name_ids = scope.where("LOWER(name) LIKE ?", like).pluck(:id)
    external_id_ids = scope.where("LOWER(external_id) LIKE ?", like).pluck(:id)
    results = scope
      .where(id: (exact_email_ids + name_ids + external_id_ids).uniq)
      .order(:email)
      .limit(10)

    render json: results.map { |s|
      {
        id: s.id,
        email: s.email,
        name: s.name,
        external_id: s.external_id,
        subscribed: s.subscribed
      }
    }
  end

  # GET /account/subscribers/:id
  # GET /account/subscribers/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/subscribers/new
  def new
  end

  # GET /account/subscribers/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/subscribers
  # POST /account/teams/:team_id/subscribers.json
  def create
    respond_to do |format|
      if @subscriber.save
        format.html { redirect_to [:account, @subscriber], notice: I18n.t("subscribers.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @subscriber] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @subscriber.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/subscribers/:id
  # PATCH/PUT /account/subscribers/:id.json
  def update
    respond_to do |format|
      if @subscriber.update(subscriber_params)
        format.html { redirect_to [:account, @subscriber], notice: I18n.t("subscribers.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @subscriber] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @subscriber.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/subscribers/:id
  # DELETE /account/subscribers/:id.json
  def destroy
    @subscriber.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :subscribers], notice: I18n.t("subscribers.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
