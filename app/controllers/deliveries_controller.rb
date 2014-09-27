class DeliveriesController < ApplicationController
  layout false

  skip_before_filter :verify_authenticity_token
  skip_authorization_check
  skip_before_action :authenticate_user!
  before_filter :load_from_delivery_key

  def opened
    if @delivery
      @delivery.opened!
    end

    image = File.read(File.join(Rails.root, "public/1x1.gif"))
    send_data image, :type => "image/gif", :disposition => "inline"
  end

  def delivered
    @delivery.delivered!
    render :text => "Ok: delivered at #{@delivery.delivered_at}."
  end

  def bounce
    @delivery.bounce!
    render :text => "Ok: #{@delivery.bounces_count} bounces. Last at #{@delivery.bounced_at}\n#{@delivery.subscription.subscription_status.capitalize}"
  end

  def complaint
    @delivery.complaint!
    render :text => "Ok: #{@delivery.complaints_count} complaints.\n#{@delivery.subscription.subscription_status.capitalize}"
  end

  private
    def load_from_delivery_key
      if !request.raw_post.blank?

        hash = JSON.parse(request.raw_post)

        if hash['Type'] && hash['Type'].eql?('SubscriptionConfirmation')
          puts "SNS SUBSCIPTION CONFIRMATION:\n---------------------\n"
          puts hash.inspect
          puts "SNS SUBSCIPTION CONFIRMATION:\n---------------------\n"

          render json: hash and return
        end

        puts "SNS NOTIFICATION -------------\n"
        puts hash
        puts "SNS MESSAGE -------------\n"
        puts JSON.parse(hash["Message"])

        if message = JSON.parse(hash["Message"])
          mail = message['mail']
          source = mail['source']

          delivery_key = source.match(/bounces-(.*)\@/)[1]

          @delivery = Delivery.where(key: delivery_key).first

          render text: "Not found", status: :not_found and return unless @delivery

        end
      elsif !params[:key].blank?
         @delivery = Delivery.where(key: params[:key]).first
      else
        render text: "No post data" and return
      end
    end


end
