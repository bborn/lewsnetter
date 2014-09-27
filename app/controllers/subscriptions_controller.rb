class SubscriptionsController < ApplicationController
  load_resource :find_by => :email_key
  skip_load_resource :only => [:create, :new]
  skip_authorization_check
  skip_before_action :authenticate_user!

  def unsubscribe
    @subscription.unsubscribe!
    redirect_to subscription_path(@subscription.mail_key)
  end

  def subscribe
    @subscription.subscribe!
    redirect_to subscription_path(@subscription.mail_key)
  end

  def confirm
    @subscription.update_attributes(confirmed: true)
    @subscription.send_welcome_email
    redirect_to subscription_path(@subscription.mail_key)
  end

  def show
  end

  def create
    @subscription = Subscription.find_or_initialize_by(:email => subscription_params.delete(:email))
    @subscription.attributes = subscription_params
    @subscription.subscribed = true

    if @subscription.save
      if @subscription.id_changed?
        flash[:notice] = 'You are subscribed. Please check your e-mail to confirm your address (we will not smart e-mailing you until you have done this).'
      else
        flash[:notice] = 'Your subscription has been updated'
      end
    else
      render :new
    end
  end

  def new
    @subscription = Subscription.new(params[:subscription])
  end

  private
    def subscription_params
      params[:subscription].permit(:email, :name, :mailing_list_ids => [])
    end


end
