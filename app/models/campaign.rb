require 'uri'

module Smailer
  module Models
    class MailCampaign < ActiveRecord::Base

      def body_html
        #get the Campaign
        campaign = Campaign.find(self.id)
        campaign.body_html
      end

    end
  end
end


class Campaign < Smailer::Models::MailCampaign
  include AASM

  belongs_to :mailing_list, inverse_of: :campaigns
  belongs_to :template
  serialize :content_json, JSON

  attr_accessor :preview_recipients

  before_save do
    if self.content_json_changed? && self.content_json_was.blank?
      self.draft
    end
  end

  aasm :whiny_transitions => false do
    state :created, :initial => true
    state :drafted
    state :queueing
    state :queued
    state :sending
    state :sent

    event :draft do
      transitions :from => [:drafted, :created, :queued], :to => :drafted
    end

    event :queue do
      transitions :from => :drafted, :to => :queueing
      after do
        self.delay.create_queued_mails
      end
    end

    event :queued do
      transitions :from => :queueing, :to => :queued
    end

    event :send_campaign do
      transitions :from => :queued, :to => :sending
      after do
        self.enqueue_campaign_workers
      end
    end

    event :sent do
      transitions :from => :sending, :to => :sent
    end
  end

  def deliveries
    finished_mails
  end

  def state
    aasm_state
  end

  def create_queued_mails
    batch_size = Setting.get_with_default('queue.batch_size', 100).to_f

    self.subscribers.find_each(batch_size: batch_size) do |subscription|
      QueuedMailCreator.perform_async(self.id, subscription.email)
    end

    self.delay_for(Setting.get_with_default('queue.checkup_delay', 300).seconds).check_if_queued
  end

  def check_if_queued
    if self.queued? || self.queued_mails.count.eql?(self.subscribers.count)
      self.queued!
    else
      self.delay_for(5.minutes).check_if_queued
    end
  end


  def enqueue_campaign_workers
    qm_count = self.queued_mails.count

    unless qm_count.zero?
      batch_size   = (Setting.get('queue.batch_size') || 100).to_f
      worker_count = (qm_count/batch_size).ceil

      logger.debug "Run #{worker_count} workers: \n"

      worker_count.times do |i|
        logger.debug "\n -------- Worker #{i} --------"
        limit = batch_size
        CampaignWorker.perform_async(self.id, limit)
        sleep(1) #avoid race conditions
      end
    end
  end

  def templated_body_html
    return unless self.template
    if self.content_json.blank?
      return read_attribute(:body_html)
    end

    string = self.template.html

    html_doc = Nokogiri::HTML(string)
    html_doc.encoding = 'UTF-8'

    hash = JSON.parse(self.content_json)
    hash.each do |key, value|
      html_doc.at_css("##{key}").inner_html = value['value']
    end

    html_string = html_doc.to_s
    inlined_string = Premailer.new(html_string,  warn_level: Premailer::Warnings::SAFE, with_html_string: true).to_inline_css

    #nokogiri/premailer tries to escape our interpolations. put them back
    inlined_string = inlined_string.gsub(/\%\%7B(.*?)\%7D/, '%{\1}')

    inlined_string = add_ga_tracking(inlined_string)

    inlined_string = add_custom_interpolations(inlined_string)

    inlined_string
  end

  def body_html
    templated_body_html
  end

  def add_custom_interpolations(text)
    return text if text.nil?

    datetime = DateTime.now
    {
      currentdayname:         lambda { datetime.strftime("%a") },
      currentday:             lambda { datetime.strftime("%-d") },
      currentmonthname:       lambda { datetime.strftime("%B") },
      currentyear:            lambda { datetime.strftime("%Y") },
      unsubscribe:            lambda { "<a href=\"http://#{ENV['MAIL_HOST']}/subscriptions/%{email_key}/unsubscribe\">unsubscribe</a>" },
      webversion:             lambda { "<a href=\"http://#{ENV['MAIL_HOST']}/campaigns/%{message_key}/webview\">View web version</a>" }
    }.each do |variable, interpolation|
      text.gsub! "%{#{variable}}" do
        interpolation.respond_to?(:call) ? interpolation.call : interpolation.to_s.html_safe
      end
    end

    text
  end

  def add_ga_tracking(html)
    # add tracking pixel
    html = html.gsub("</body>", "<img src='http://#{ENV['MAIL_HOST']}/opened?key=%{message_key}' ></body>")

    # add utm_params to links
    html = html.gsub(/href=[\'\"](.*?)[\'\"]/){|match|
      begin
        uri = URI.parse($1)
        ga = {
          source: "Newsletter",
          medium: "email",
          campaign: subject
        }

        params = []
        ga.each {|key, value|
          (params += (URI.decode_www_form(uri.query || "") << ["utm_#{key}", value])).inspect
        }

        uri.query = URI.encode_www_form(params)

        match.sub($1, uri.to_s)
      rescue URI::InvalidURIError
        match
      end
    }

    html
  end

  def send_preview
    campaign = self

    rails_delivery_method = if Smailer::Compatibility.rails_3_or_4?
      method = Rails.configuration.action_mailer.delivery_method
      [ActionMailer::Base.delivery_methods[method], ActionMailer::Base.send("#{method}_settings")]
    else
      [ActionMailer::Base.delivery_method]
    end

    Mail.defaults do
      delivery_method *rails_delivery_method
    end

    self.preview_recipients.split(',').each do |address|
      qm = QueuedMail.new
      qm.mail_campaign = self
      qm.to = address

      html_body = qm.body_html

      mail = Mail.new do
        from    campaign.from
        to      address
        subject campaign.subject

        text_part { body campaign.body_text }
        html_part { body html_body; content_type 'text/html; charset=UTF-8' }
      end
      mail.raise_delivery_errors = true
      mail.deliver
    end
  end

  def body_text_from_json
    return "" if content_json.blank?
    html = ""

    JSON.parse(content_json).each do |key, value|
      html << value['value']
    end

    HtmlToPlainText.plain_text(html)
  end


  def last_feed_used
    mailing_list.feed
  end

  def subscribers
    mailing_list.subscribers
  end

  def unopened_count
    subscribers.count - opened_mails_count
  end

  def complaints_count
    deliveries.sum(:complaints_count)
  end


end
