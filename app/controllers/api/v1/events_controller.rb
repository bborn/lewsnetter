# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::EventsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :event, through: :subscriber, through_association: :events

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

    private

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
