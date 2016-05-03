# CanCan Abilities
#
# See the wiki for details:
# https://github.com/ryanb/cancan/wiki/Defining-Abilities

class Ability
  include CanCan::Ability

  def initialize(user = User.new)
    alias_action :create, :read, :update, to: :cru

    can :manage, User, id: user.id
    can :manage, Authentication, user_id: user.id

    can :access, :ckeditor   # needed to access Ckeditor filebrowser
    can [:read, :create, :destroy], Ckeditor::Picture
    can [:read, :create, :destroy], Ckeditor::AttachmentFile        

    can :manage, Campaign
    cannot :destroy, Campaign

    can :manage, MailingList
    cannot :destroy, MailingList

    if user.is_admin? && defined? RailsAdmin
      # Allow everything
      can :manage, :all

      # RailsAdmin
      # https://github.com/sferik/rails_admin/wiki/CanCan
      # can :access, :rails_admin
      # can :dashboard

      # RailsAdmin checks for `collection` scoped actions:
      # can :index, Model             # included in :read
      # can :new, Model               # included in :create
      # can :export, Model
      # can :history, Model           # for HistoryIndex
      # can :destroy, Model           # for BulkDelete

      # RailsAdmin checks for `member` scoped actions:
      # can :show, Model, object      # included in :read
      # can :edit, Model, object      # included in :update
      # can :destroy, Model, object   # for Delete
      # can :history, Model, object   # for HistoryShow
      # can :show_in_app, Model, object
    end
  end
end
