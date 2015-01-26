require 'spec_helper'

describe Delivery do
  let(:delivery) {
    sub = FactoryGirl.create(:subscription, email: 'test@test.com')
    campaign = FactoryGirl.create(:campaign)
    sub.mailing_lists << campaign.mailing_list
    sub.save!

    delivery = FactoryGirl.build(:delivery, to: sub.email, mail_campaign: campaign)
    delivery.save!
    delivery
  }

  context 'on create' do
    it 'should set subscription' do
      delivery.subscription.should_not == nil
      delivery.subscription.deliveries.should include(delivery)
    end
  end

  context 'with 1 or more complaints' do
    it "unsubscribes the subscription" do

      delivery.subscription.subscribed.should == true

      delivery.complaint!

      delivery.subscription.subscribed.should == false
    end
  end

  context 'with 2 or more bounces' do
    it "unsubscribes the subscription" do
      subscription = delivery.subscription

      subscription.subscribed.should == true

      delivery.bounce!

      subscription.subscribed.should == true

      delivery2 = FactoryGirl.build(:delivery, mail_campaign: delivery.campaign, to: delivery.to )
      delivery2.save!

      delivery2.subscription.should == subscription

      delivery2.bounce!

      subscription.reload.subscribed.should == false
    end
  end



end
