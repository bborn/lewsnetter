class Subscription < ActiveRecord::Base
  has_and_belongs_to_many :mailing_lists, -> { uniq }
  has_many :deliveries, class_name: 'Smailer::Models::FinishedMail'

  validates_uniqueness_of :email
  validates_format_of :email, :with => /@/

  after_create :generate_mail_key
  after_create :send_confirmation_email
  attr_accessor :importing


  def self.confirmed
    where(confirmed: true)
  end

  def self.subscribed
    where(subscribed: true)
  end

  def unsubscribe!
    update_attributes(subscribed: false)
  end

  def subscribe!
    update_attributes(subscribed: true)
  end

  def self.find_by_email_key!(key)
    email = Smailer::Models::MailKey.find_by_key(key).try(:email)
    raise ActiveRecord::RecordNotFound unless email
    Subscription.where(email: email).first
  end

  def mail_key
    Smailer::Models::MailKey.find_by_email(email).try(:key)
  end

  def generate_mail_key
    Smailer::Models::MailKey.get(self.email)
  end

  def send_confirmation_email
    unless self.importing
      SubscriptionMailer.delay.confirmation_email(self.id)
    end
  end

  def send_welcome_email
    SubscriptionMailer.delay.welcome_email(self.id)
  end

  def bounces_count
    deliveries.sum(:bounces_count)
  end

  def complaints_count
    deliveries.sum(:complaints_count)
  end

  def opens_count
    deliveries.where("opens_count IS NOT NULL").count
  end

  def hit_rate
    return nil if deliveries.count == 0
    opens_count.to_f / deliveries.count
  end

  def subscription_status
    subscribed? ? 'subscribed' : 'unsubscribed'
  end

end
