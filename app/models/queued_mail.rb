class QueuedMail < Smailer::Models::QueuedMail

  def campaign
    Campaign.find mail_campaign.id
  end

  def deliver
    #first, abort if this thing has already been sent
    if campaign.deliveries.where(key: self.key).any?
      self.destroy
    else
      do_mail_delivery
    end
  end

  def do_mail_delivery
    method = Rails.configuration.action_mailer.delivery_method
    rails_delivery_method = [ActionMailer::Base.delivery_methods[method], ActionMailer::Base.send("#{method}_settings")]

    Mail.defaults do
      delivery_method *rails_delivery_method
    end

    return_path_domain = ENV['MAIL_HOST']
    verp = !return_path_domain.blank?

    # try to send the email
    mail = self.construct_mail(verp, return_path_domain)

    self.last_retry_at = Time.now
    self.retries      += 1

    begin
      # commense delivery
      mail.deliver
    rescue Exception => e
      # failed, we have.
      self.last_error = "#{e.class.name}: #{e.message}"

      # check if the message hasn't expired;
      if self.retries_exceeded? || self.too_old?
        # the message has expired; move to finished_mails
        Smailer::Models::FinishedMail.add(self, Smailer::Models::FinishedMail::Statuses::FAILED)
      end

      self.locked        = false # unlock this email
      self.save
      return [self, :failed]
    else
      #the delivery succeeded
      Smailer::Models::FinishedMail.add(self, Smailer::Models::FinishedMail::Statuses::SENT)
      return [self, :sent]
    end


  end

  def retries_exceeded?
    max_retries  = Setting.get_with_default('queue.max_retries', 0).to_i

    max_retries  > 0 && self.retries >= max_retries
  end

  def too_old?
    max_lifetime = Setting.get_with_default('queue.max_lifetime', 172800).to_i
    max_lifetime > 0 && (Time.now - self.created_at) >= max_lifetime
  end

  def construct_mail(verp = nil, return_path_domain = nil)
    # validate options
    if verp && return_path_domain.blank?
      raise "VERP is enabled, but a :return_path_domain option has not been specified or is blank."
    end

    queued_mail = self
    mail = Mail.new do
      from    queued_mail.from
      to      queued_mail.to
      subject queued_mail.subject

      queued_mail.campaign.attachments.each do |attachment|
        add_file :filename => attachment.filename,
                 :content => attachement.body
      end

      text_part { body queued_mail.body_text }
      html_part { body queued_mail.body_html; content_type 'text/html; charset=UTF-8' }
    end
    mail.raise_delivery_errors = true

    # compute the VERP'd return_path if requested
    # or fall-back to a global return-path if not
    item_return_path = if verp
       "#{Smailer::BOUNCES_PREFIX}#{self.key}@#{return_path_domain}"
    end

    # set the return-path, if any
    if item_return_path
      mail.return_path   = item_return_path
      mail['Errors-To']  = item_return_path
      mail['Bounces-To'] = item_return_path
    end

    return mail
  end

  rails_admin do
  end

end
