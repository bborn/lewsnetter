# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::SubscribersController < Api::V1::ApplicationController
    account_load_and_authorize_resource :subscriber, through: :team, through_association: :subscribers

    # GET /api/v1/teams/:team_id/subscribers
    def index
    end

    # GET /api/v1/subscribers/:id
    def show
    end

    # POST /api/v1/teams/:team_id/subscribers
    def create
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
        )

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
