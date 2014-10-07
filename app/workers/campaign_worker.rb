class CampaignWorker
  include Sidekiq::Worker
  sidekiq_options :queue => :campaigns

  def perform(id, limit = nil)
    campaign = Campaign.find(id)
    deliver(campaign, limit)
  end

  def deliver(campaign, limit = nil)
    logger.debug "Delivering limit: #{limit}\n"

    # clean up any old locked items
    expired_locks_condition = ['locked = ? AND locked_at <= ?', true, (Setting.get_with_default('queue.expire_locks_in', 1).minutes.ago.utc)]
    campaign.queued_mails.where(expired_locks_condition).update_all(:locked => false)

    # load the queue items to process
    queue_sort_order = 'retries ASC, id ASC'

    items_to_process = []

    QueuedMail.transaction do
      items_to_process = campaign.queued_mails.where(:locked => false).order(queue_sort_order).limit(limit)
      # lock the queue items
      lock_condition = {:id => items_to_process.map(&:id)}
      lock_update = {:locked => true, :locked_at => Time.now.utc}
      campaign.queued_mails.where(lock_condition).update_all(lock_update)
    end

    items_to_process.each do |queue_item|
      logger.debug "QueuedMail: #{queue_item.id}\n"
      QueuedMailSender.perform_async(queue_item.id)
    end

    if campaign.queued_mails.any?
      CampaignWorker.perform_in(10.seconds, campaign.id, limit)
    else
      campaign.sent!
    end
  end

end
