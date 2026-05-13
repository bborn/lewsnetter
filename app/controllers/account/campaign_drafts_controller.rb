class Account::CampaignDraftsController < Account::ApplicationController
  # POST /account/campaigns/:id/draft
  #
  # Runs AI::CampaignDrafter against the brief + (optional) segment and renders
  # a "draft" frame containing subject candidates + body, which the campaign
  # form merges into the current form fields.
  #
  # Like SegmentTranslationsController this is a member POST that needs the
  # campaign loaded by `params[:id]`. `account_load_and_authorize_resource` only
  # supports `:create` as a *collection* action (no id in the URL), so we
  # resolve + authorize manually against the campaign.
  def create
    @campaign = Campaign.find(params[:id])
    authorize! :update, @campaign

    # When the request body is JSON (the live editor's `ai-drafter` Stimulus
    # controller), Rails parses it into `params` but only when the request
    # parser kicks in. We accept both JSON and form-encoded for resilience.
    brief = (params[:brief].presence || params.dig(:draft, :brief)).to_s
    segment = @campaign.segment || @campaign.team.segments.find_by(id: params[:segment_id])
    tone = params[:tone].to_s.presence

    @draft = AI::CampaignDrafter.new(
      team: @campaign.team,
      brief: brief,
      segment: segment,
      tone: tone
    ).call

    respond_to do |format|
      format.json { render json: draft_as_json(@draft) }
      format.html { render partial: "account/campaigns/draft", locals: {draft: @draft, campaign: @campaign} }
      format.turbo_stream { render partial: "account/campaigns/draft", formats: [:html], locals: {draft: @draft, campaign: @campaign} }
    end
  end

  private

  # Serializes a Draft for the live editor. The editor wants a flat shape:
  # body_markdown is what the EasyMDE textarea consumes, subjects is an
  # ordered list (first wins by convention), preheader fills its own input.
  # We surface `stub` so the UI can label stub-mode output for the author.
  def draft_as_json(draft)
    {
      body_markdown: draft.markdown_body.to_s,
      preheader: draft.preheader.to_s,
      subjects: Array(draft.subject_candidates).map(&:subject),
      suggested_send_time: draft.suggested_send_time.to_s,
      stub: draft.respond_to?(:stub?) ? draft.stub? : false,
      errors: Array(draft.errors)
    }
  end
end
