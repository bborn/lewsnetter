class QueuedMailSender
  include Sidekiq::Worker
  sidekiq_options :queue => :queued_mails, :unique => true, :unique_job_expiration => (120 * 60), :retry => false
  #retry is false because we're already rescuing failed mail.delivers and putting them back in the queue

  def perform(id)
    queued_mail = QueuedMail.find(id)
    queued_mail.deliver
  end

end
