class Account::SegmentsController < Account::ApplicationController
  account_load_and_authorize_resource :segment, through: :team, through_association: :segments

  # GET /account/teams/:team_id/segments
  # GET /account/teams/:team_id/segments.json
  def index
    delegate_json_to_api
  end

  # GET /account/segments/:id
  # GET /account/segments/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/segments/new
  def new
  end

  # GET /account/segments/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/segments
  # POST /account/teams/:team_id/segments.json
  def create
    respond_to do |format|
      if @segment.save
        format.html { redirect_to [:account, @segment], notice: I18n.t("segments.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @segment] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @segment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/segments/:id
  # PATCH/PUT /account/segments/:id.json
  def update
    respond_to do |format|
      if @segment.update(segment_params)
        format.html { redirect_to [:account, @segment], notice: I18n.t("segments.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @segment] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @segment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/segments/:id
  # DELETE /account/segments/:id.json
  def destroy
    @segment.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :segments], notice: I18n.t("segments.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  # POST /account/teams/:team_id/segments/preview
  # Used by the visual builder — accepts an in-flight rule tree (JSON in
  # `rules` param), compiles to SQL, returns matching count + up to 5
  # sample subscriber rows (with the rule-referenced field values surfaced
  # so the user can verify their filter is doing what they expect).
  # Doesn't persist anything.
  def preview
    tree = JSON.parse(params[:rules].to_s) rescue nil
    sql = nil
    if tree.is_a?(Hash)
      begin
        sql = Segments::PredicateCompiler.new(tree, team: current_team).to_sql
      rescue Segments::PredicateCompiler::InvalidTree => e
        return render json: {error: e.message}, status: :unprocessable_entity
      end
    end

    scope = current_team.subscribers
    needs_company_join = sql&.include?("companies.") || referenced_fields(tree).any? { |k| k.start_with?("companies.", "company_attributes.") }
    scope = scope.joins(:company) if needs_company_join
    scope = scope.where(sql) if sql.present?

    count = scope.count
    field_refs = referenced_fields(tree)
    sample = scope.order(:id).limit(5).map do |s|
      {
        id: s.id,
        email: s.email,
        name: s.name,
        subscribed: s.subscribed,
        attrs: field_refs.map { |key| {label: humanize_field(key), value: extract_value(s, key)} }
      }
    end

    render json: {count: count, sample: sample, sql: sql}
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end

  # Walk the rule tree and return the unique set of field keys it references.
  # The visual builder uses these to surface the relevant column values on
  # each sample row so users can debug why a row matched (or didn't).
  def referenced_fields(tree)
    return [] unless tree.is_a?(Hash)
    fields = []
    walk = ->(node) {
      case node["type"]
      when "group" then (node["rules"] || []).each(&walk)
      when "rule"  then fields << node["field"] if node["field"].present?
      end
    }
    walk.call(tree)
    # De-dupe but drop noise fields the row card already shows (email/name).
    # Drop encrypted fields and the noise fields the row card already shows.
    fields.uniq - %w[subscribers.email subscribers.name subscribers.external_id]
  end

  def humanize_field(key)
    case key
    when /\Acustom_attributes\.(.+)\z/    then "#{$1}"
    when /\Acompany_attributes\.(.+)\z/   then "company.#{$1}"
    when /\Asubscribers\.(.+)\z/          then $1
    when /\Acompanies\.(.+)\z/            then "company.#{$1}"
    else key
    end
  end

  def extract_value(subscriber, key)
    case key
    when /\Asubscribers\.(.+)\z/
      subscriber.public_send($1)
    when /\Acompanies\.(.+)\z/
      subscriber.company&.public_send($1)
    when /\Acustom_attributes\.(.+)\z/
      (subscriber.custom_attributes || {})[$1]
    when /\Acompany_attributes\.(.+)\z/
      (subscriber.company&.custom_attributes || {})[$1]
    end
  rescue NoMethodError
    nil
  end
end
