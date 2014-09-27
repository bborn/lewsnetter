class SubscriptionMailer < ActionMailer::Base
  default from: Rails.application.config.settings.mail.from

  layout 'emails/email'

  def confirmation_email(id)
    return false unless load_subscription(id).present?
    mail to: @subscription.email, subject: I18n.t('emails.confirmation_email.subject')
  end

  def welcome_email(id)
    return false unless load_subscription(id).present?
    mail to: @subscription.email, subject: I18n.t('emails.welcome_email.subject')
  end


  protected

  def load_subscription(id)
    @subscription = Subscription.find(id)
  end

end
