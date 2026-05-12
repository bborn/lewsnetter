# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::SenderAddressesController < Api::V1::ApplicationController
    account_load_and_authorize_resource :sender_address, through: :team, through_association: :sender_addresses

    # GET /api/v1/teams/:team_id/sender_addresses
    def index
    end

    # GET /api/v1/sender_addresses/:id
    def show
    end

    # POST /api/v1/teams/:team_id/sender_addresses
    def create
      if @sender_address.save
        render :show, status: :created, location: [:api, :v1, @sender_address]
      else
        render json: @sender_address.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/sender_addresses/:id
    def update
      if @sender_address.update(sender_address_params)
        render :show
      else
        render json: @sender_address.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/sender_addresses/:id
    def destroy
      @sender_address.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      #
      # `:verified` and `:ses_status` are intentionally NOT permitted — they
      # are derived from SES via Ses::IdentityChecker on save/recheck, never
      # supplied by the user.
      def sender_address_params
        strong_params = params.require(:sender_address).permit(
          *permitted_fields,
          :email,
          :name,
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
  class Api::V1::SenderAddressesController
  end
end
