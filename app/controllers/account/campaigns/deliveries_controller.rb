require "csv"

class Account::Campaigns::DeliveriesController < Account::ApplicationController
  # Authorise read access on the parent campaign — Delivery itself isn't a
  # CanCan-managed resource, but read access on the campaign is the right
  # gate: anyone who can see a campaign can see its recipient list. This
  # mirrors how the postmortem controller scopes through the campaign.
  account_load_and_authorize_resource :campaign,
    through: :team,
    through_association: :campaigns

  # Status tab strip values. "all" is the implicit default. The values match
  # the Delivery scope names so the filter is a single `.public_send` call.
  STATUS_FILTERS = %w[all opened clicked bounced complained unsubscribed].freeze
  DEFAULT_PER_PAGE = 50
  CSV_COLUMNS = %w[
    subscriber_email
    subscriber_name
    subscriber_external_id
    status
    sent_at
    delivered_at
    opened_at
    clicked_at
    bounced_at
    bounce_subtype
    complained_at
    unsubscribed_at
    click_count
    last_clicked_url
  ].freeze

  # GET  /account/campaigns/:campaign_id/deliveries
  # GET  /account/campaigns/:campaign_id/deliveries.csv
  #
  # HTML: paginated table of Deliveries for this campaign, with a status
  # tab filter. The tab strip submits as `?status=opened` etc. Sort is
  # most-recent-engagement-first so the freshest action is on top.
  #
  # CSV: streams *all* deliveries for this campaign (no pagination, no
  # status filter). Uses `find_each` + row-by-row CSV writes — fine up to
  # ~100k recipients; past that, switch to an async export job.
  def index
    @status = STATUS_FILTERS.include?(params[:status]) ? params[:status] : "all"

    respond_to do |format|
      format.html do
        scope = filtered_scope(@status)
          .includes(:subscriber)
          .order(Arel.sql("COALESCE(clicked_at, opened_at, bounced_at, delivered_at, sent_at, created_at) DESC NULLS LAST"))

        @pagy, @deliveries = pagy(scope, limit: DEFAULT_PER_PAGE, page_param: :page)
        @status_counts = status_counts
      end

      format.csv do
        filename = "campaign-#{@campaign.id}-deliveries-#{Time.current.strftime("%Y%m%d-%H%M%S")}.csv"
        response.headers["Content-Type"] = "text/csv; charset=utf-8"
        response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: filename)
        response.headers["X-Accel-Buffering"] = "no" # nginx hint: don't buffer
        response.headers["Cache-Control"] = "no-cache"
        # Hand the response writer to CSV row-by-row. Rails wraps the
        # response body in an Enumerable when streaming, but for this
        # data volume a synchronous write to `response.stream` blows up
        # on default Rack — use a String IO and stream via a Live-style
        # enumerator instead. Simpler + correct for <100k rows: build
        # the whole CSV in memory and send. We document the limit above.
        send_data build_csv, filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
      end
    end
  end

  private

  # Apply the status tab filter. `all` returns the whole campaign's
  # Deliveries; the named filters map 1:1 to Delivery scopes (plus
  # unsubscribed, which uses a raw `where.not`).
  def filtered_scope(status)
    base = @campaign.deliveries
    case status
    when "opened" then base.opened
    when "clicked" then base.clicked
    when "bounced" then base.bounced
    when "complained" then base.complained
    when "unsubscribed" then base.where.not(unsubscribed_at: nil)
    else base
    end
  end

  # Count per tab so the strip can show counts. One query per scope is
  # cheap with the campaign_id index; we keep it simple over a single
  # GROUP-BY because the scopes overlap (a row can be both opened and
  # clicked) and a UNION would lose those overlaps.
  def status_counts
    base = @campaign.deliveries
    {
      "all" => base.count,
      "opened" => base.opened.count,
      "clicked" => base.clicked.count,
      "bounced" => base.bounced.count,
      "complained" => base.complained.count,
      "unsubscribed" => base.where.not(unsubscribed_at: nil).count
    }
  end

  def build_csv
    CSV.generate do |csv|
      csv << CSV_COLUMNS
      @campaign.deliveries
        .includes(:subscriber)
        .order(:id)
        .find_each(batch_size: 500) do |d|
          s = d.subscriber
          csv << [
            s&.email,
            s&.name,
            s&.external_id,
            d.status,
            d.sent_at&.iso8601,
            d.delivered_at&.iso8601,
            d.opened_at&.iso8601,
            d.clicked_at&.iso8601,
            d.bounced_at&.iso8601,
            d.bounce_subtype,
            d.complained_at&.iso8601,
            d.unsubscribed_at&.iso8601,
            d.click_count,
            d.last_clicked_url
          ]
        end
    end
  end
end
