# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::SubscribersController < Api::V1::ApplicationController
    account_load_and_authorize_resource :subscriber, through: :team, through_association: :subscribers,
      except: [:bulk, :destroy_by_external_id]

    # GET /api/v1/teams/:team_id/subscribers
    def index
    end

    # GET /api/v1/subscribers/:id
    def show
    end

    # POST /api/v1/teams/:team_id/subscribers
    #
    # Idempotent upsert when external_id is present and matches an existing
    # subscriber on this team — the row is updated in place and 200 is
    # returned. Otherwise this falls back to vanilla create (201).
    def create
      if subscriber_params[:external_id].present?
        existing = @team.subscribers.find_by(external_id: subscriber_params[:external_id])
        if existing
          @subscriber = existing
          if @subscriber.update(subscriber_params.except(:external_id))
            render :show, status: :ok, location: [:api, :v1, @subscriber]
          else
            render json: @subscriber.errors, status: :unprocessable_entity
          end
          return
        end
      end

      if @subscriber.save
        render :show, status: :created, location: [:api, :v1, @subscriber]
      else
        render json: @subscriber.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/subscribers/:id
    def update
      if @subscriber.update(subscriber_params)
        render :show
      else
        render json: @subscriber.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/subscribers/:id
    def destroy
      @subscriber.destroy
    end

    # POST /api/v1/teams/:team_id/subscribers/bulk
    #
    # NDJSON streaming upsert — one subscriber payload per line. Designed for
    # backfill from a source app. Returns a per-row summary. Not transactional;
    # partial success is normal.
    def bulk
      @team = Team.find(params[:team_id])
      authorize! :create, @team.subscribers.new

      summary = {processed: 0, created: 0, updated: 0, errors: []}
      body = request.body
      body.rewind if body.respond_to?(:rewind)
      body.each_line.with_index(1) do |raw, line_number|
        line = raw.strip
        next if line.empty?

        summary[:processed] += 1
        begin
          row = JSON.parse(line).deep_symbolize_keys
          row[:custom_attributes] = row.delete(:attributes) if row.key?(:attributes)

          if row[:external_id].present? && (existing = @team.subscribers.find_by(external_id: row[:external_id]))
            existing.update!(row.slice(:email, :name, :subscribed, :custom_attributes))
            summary[:updated] += 1
          else
            @team.subscribers.create!(row.slice(:external_id, :email, :name, :subscribed, :custom_attributes))
            summary[:created] += 1
          end
        rescue JSON::ParserError => e
          summary[:errors] << {line: line_number, error: "Invalid JSON: #{e.message}"}
        rescue ActiveRecord::RecordInvalid => e
          summary[:errors] << {line: line_number, error: e.record.errors.full_messages.to_sentence}
        rescue => e
          summary[:errors] << {line: line_number, error: e.message}
        end
      end

      render json: summary
    end

    # DELETE /api/v1/teams/:team_id/subscribers/by_external_id/:external_id
    #
    # GDPR-style hard delete by source-app external_id, so the caller doesn't
    # need to know the internal Lewsnetter ID.
    def destroy_by_external_id
      @team = Team.find(params[:team_id])
      target = @team.subscribers.find_by!(external_id: params[:external_id])
      authorize! :destroy, target
      target.destroy
      head :no_content
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def subscriber_params
        strong_params = params.require(:subscriber).permit(
          *permitted_fields,
          :external_id,
          :email,
          :name,
          :subscribed,
          # 🚅 super scaffolding will insert new fields above this line.
          *permitted_arrays,
          # 🚅 super scaffolding will insert new arrays above this line.
          custom_attributes: {}
        )

        # The API surfaces `attributes:` to source apps (Intercom-style); we
        # store it as `custom_attributes` because ActiveRecord reserves
        # `attributes` as an instance method name.
        if params[:subscriber].respond_to?(:key?) && params[:subscriber].key?(:attributes)
          strong_params[:custom_attributes] = params[:subscriber][:attributes].permit!.to_h
        end

        process_params(strong_params)

        strong_params
      end
    end

    include StrongParameters
  end
else
  class Api::V1::SubscribersController
  end
end
