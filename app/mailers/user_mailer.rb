class UserMailer < ActionMailer::Base
  default from: Setting.get_with_default('mail.from', Rails.application.config.settings.mail.from)
  layout 'emails/email'

  def welcome_email(user)
    return false unless load_user(user).present?
    mail to: @user.email, subject: I18n.t('emails.welcome.subject')
  end

  def campaign_notification(campaign)
    users = User.where(is_admin: true).map(&:email)
    @campaign = campaign
    mail to: users, subject: "Campaign #{campaign.id} status: #{campaign.state}"
  end

  protected

  def load_user(user)
    @user = user.is_a?(User) ? user : User.find(user)
  end
end
