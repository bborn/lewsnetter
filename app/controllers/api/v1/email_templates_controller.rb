# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::EmailTemplatesController < Api::V1::ApplicationController
    account_load_and_authorize_resource :email_template, through: :team, through_association: :email_templates

    # GET /api/v1/teams/:team_id/email_templates
    def index
    end

    # GET /api/v1/email_templates/:id
    def show
    end

    # POST /api/v1/teams/:team_id/email_templates
    def create
      if @email_template.save
        render :show, status: :created, location: [:api, :v1, @email_template]
      else
        render json: @email_template.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/email_templates/:id
    def update
      if @email_template.update(email_template_params)
        render :show
      else
        render json: @email_template.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/email_templates/:id
    def destroy
      @email_template.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def email_template_params
        strong_params = params.require(:email_template).permit(
          *permitted_fields,
          :name,
          :mjml_body,
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
  class Api::V1::EmailTemplatesController
  end
end
