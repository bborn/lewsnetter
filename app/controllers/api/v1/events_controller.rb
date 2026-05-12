# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::EventsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :event, through: :subscriber, through_association: :events,
      except: [:track, :bulk]

    # GET /api/v1/subscribers/:subscriber_id/events
    def index
    end

    # GET /api/v1/events/:id
    def show
    end

    # POST /api/v1/subscribers/:subscriber_id/events
    def create
      if @event.save
        render :show, status: :created, location: [:api, :v1, @event]
      else
        render json: @event.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/events/:id
    def update
      if @event.update(event_params)
        render :show
      else
        render json: @event.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/events/:id
    def destroy
      @event.destroy
    end

    # POST /api/v1/teams/:team_id/events/track
    #
    # Push-API entry point. Resolves the subscriber by external_id (per team),
    # optionally auto-creating it when `auto_create: true` and an email is
    # supplied — convenient for source apps that emit events before formally
    # registering the user.
    def track
      team = find_team_for_push
      authorize! :create, team.events.new

      payload = track_params
      external_id = payload[:external_id].presence
      return render(json: {error: "external_id is required"}, status: :bad_request) unless external_id

      subscriber = team.subscribers.find_by(external_id: external_id)
      if subscriber.nil?
        if payload[:auto_create] && payload[:email].present?
          subscriber = team.subscribers.create!(
            external_id: external_id,
            email: payload[:email],
            name: payload[:name]
          )
        else
          return render(json: {error: "Subscriber not found for external_id=#{external_id}"}, status: :not_found)
        end
      end

      @event = subscriber.events.create!(
        team: team,
        name: payload[:name_event] || payload[:event_name] || payload[:event],
        occurred_at: payload[:occurred_at] || Time.current,
        properties: payload[:properties] || {}
      )
      render :show, status: :created, location: [:api, :v1, @event]
    end

    # POST /api/v1/teams/:team_id/events/bulk
    #
    # NDJSON streaming bulk event ingestion. One event payload per line. Returns
    # a summary tallying created vs error rows. Not transactional.
    def bulk
      team = find_team_for_push
      authorize! :create, team.events.new

      summary = {processed: 0, created: 0, errors: []}
      body = request.body
      body.rewind if body.respond_to?(:rewind)
      body.each_line.with_index(1) do |raw, line_number|
        line = raw.strip
        next if line.empty?

        summary[:processed] += 1
        begin
          row = JSON.parse(line).deep_symbolize_keys
          external_id = row[:external_id]
          subscriber = team.subscribers.find_by(external_id: external_id)

          if subscriber.nil?
            summary[:errors] << {line: line_number, error: "Subscriber not found for external_id=#{external_id}"}
            next
          end

          subscriber.events.create!(
            team: team,
            name: row[:name] || row[:event],
            occurred_at: row[:occurred_at] || Time.current,
            properties: row[:properties] || {}
          )
          summary[:created] += 1
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

    private

    def find_team_for_push
      Team.find(params[:team_id])
    end

    def track_params
      params.permit(
        :external_id, :email, :name, :auto_create,
        :name_event, :event_name, :event,
        :occurred_at,
        properties: {}
      )
    end

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def event_params
        strong_params = params.require(:event).permit(
          *permitted_fields,
          :name,
          :occurred_at,
          # 🚅 super scaffolding will insert new fields above this line.
          *permitted_arrays,
          # 🚅 super scaffolding will insert new arrays above this line.
          properties: {}
        )

        process_params(strong_params)

        strong_params
      end
    end

    include StrongParameters
  end
else
  class Api::V1::EventsController
  end
end
