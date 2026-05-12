# Subscribers::Import is a Bullet Train "action model" — an AR record that
# owns the inputs (uploaded CSV) and outputs (counts + errors_log) of a
# side-effectful operation, processed via ImportSubscribersJob.
#
# Authorization is loaded through the parent Team; CanCan picks up
# permissions for Subscribers::Import from config/models/roles.yml.
class Account::Subscribers::ImportsController < Account::ApplicationController
  account_load_and_authorize_resource :import,
    class: "Subscribers::Import",
    through: :team,
    through_association: :subscriber_imports

  # GET /account/teams/:team_id/subscribers/imports
  def index
  end

  # GET /account/teams/:team_id/subscribers/imports/new
  def new
  end

  # POST /account/teams/:team_id/subscribers/imports
  def create
    @import.status ||= "pending"

    if @import.save
      ImportSubscribersJob.perform_later(@import.id)
      redirect_to account_subscribers_import_path(@import),
        notice: I18n.t("subscribers/imports.notifications.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /account/subscribers/imports/:id
  def show
  end

  private

  def import_params
    params.require(:subscribers_import).permit(:csv, :notes)
  end

  def process_params(strong_params)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
