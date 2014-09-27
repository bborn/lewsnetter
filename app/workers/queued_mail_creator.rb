class QueuedMailCreator
  include Sidekiq::Worker
  sidekiq_options :queue => :queued_mails, :unique => true, :unique_job_expiration => (120 * 60), :retry => 5

  def perform(campaign_id, email)
    Smailer::Models::QueuedMail.create(to: email, mail_campaign_id: campaign_id)
  end

end
