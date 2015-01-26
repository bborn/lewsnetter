class Delivery < Smailer::Models::FinishedMail
  MAX_BOUNCES = 2
  MAX_COMPLAINTS = 1
  before_create :set_subscription
  belongs_to :subscription, inverse_of: :deliveries

  # def see!(request)
  #   self.ip_address = request.remote_ip if ip_address.blank?
  #   self.user_agent = request.user_agent if user_agent.blank?
  #   self.seen_at = Time.now if seen_at.nil?
  #   save
  # end

  # def click!(request)
  #   self.ip_address = request.remote_ip if ip_address.blank?
  #   self.user_agent = request.user_agent if user_agent.blank?
  #   self.seen_at = Time.now if seen_at.nil?
  #   self.clicked_at = Time.now if clicked_at.nil?
  #   save
  # end

  def campaign
    mail_campaign
  end

  def google_analytics_id
    campaign.mailing_list.google_analytics_id
  end

  def track_google_analytics
    tracker = Staccato.tracker(google_analytics_id)
    tracker.event(
      category: 'Newsletter',
      action: 'opened',
      label: "#{self.mail_campaign.created_at} #{self.subject}",
      value: 1)
  end

  def opened!
    track_google_analytics if google_analytics_id
    super
    new_count = self.opens_count+1
    update_attributes({opened_at: Time.now, opens_count: new_count})
  end


  def delivered!
    update_attribute(:delivered_at, Time.now)
  end

  def bounce!
    new_count = self.bounces_count+1

    update_attributes({bounced_at: Time.now, bounces_count: new_count})

    subscription.unsubscribe! if subscription.bounces_count >= MAX_BOUNCES
  end

  def complaint!
    new_count = self.complaints_count+1

    update_attributes({complaints_count: new_count})

    subscription.unsubscribe! if subscription.complaints_count >= MAX_COMPLAINTS
  end

  def set_subscription
    self.subscription = Subscription.find_by_email(self.to)
  end

  rails_admin do
  end

end
