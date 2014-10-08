require 'spec_helper'

describe Delivery do
  let(:delivery) {
    delivery = FactoryGirl.build(:delivery)
    sub = FactoryGirl.create(:subscription, email: delivery.to)
    sub.mailing_lists << delivery.mail_campaign.mailing_list
    sub.save!

    delivery.subscription = sub
    delivery.save!

    delivery
  }

  context 'with 1 or more complaints' do
    it "unsubscribes the subscription" do

      delivery.subscription.subscribed.should == true

      delivery.complaint!

      delivery.subscription.subscribed.should == false
    end
  end

  context 'with 2 or more bounces' do
    it "unsubscribes the subscription" do
      delivery.subscription.subscribed.should == true

      delivery.bounce!
      delivery.bounce!

      delivery.subscription.subscribed.should == false
    end
  end



end
