require 'spec_helper'

describe CampaignWorker do
  let(:campaign) { FactoryGirl.create(:campaign) }


  describe "#deliver" do

    it "handles concurrent workers correctly" do
      Sidekiq::Testing.inline!
      CampaignWorker.stub(:perform_in) do |args|
        # inline makes jobs exectute immediately
        # and Sidekiq is so fast it does perform_in before all the other workers get going
        false
      end

      20.times do |i|
        sub = FactoryGirl.create(:subscription)
        sub.mailing_lists << campaign.mailing_list
      end

      campaign.subscribers.count.should == 20

      Setting.stub(:get).and_return(2)

      campaign.draft!

      campaign.drafted?.should == true

      campaign.queue!
      campaign.queued!

      campaign.queued?.should == true

      campaign.queued_mails.count.should == 20

      campaign.send_campaign!

      campaign.queued_mails.count.should == 0

    end

  end

end
