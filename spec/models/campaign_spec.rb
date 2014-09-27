require 'spec_helper'

describe Campaign do
  let(:campaign) { FactoryGirl.create(:campaign) }

  describe '#send_campaign!' do
    before(:each) do
      campaign.aasm_state = 'queued'
      campaign.save!
    end

    it "transitions from queued to sending" do
      campaign.send_campaign!
      campaign.sending?.should be_true
    end

    context 'with 1000 queued mails' do
      before do
        queued_mails = 'Array'
        queued_mails.stub(:count).and_return(1000)
        campaign.stub(:queued_mails).and_return(queued_mails)
      end

      it "enqueues 10 campaign worker jobs" do
        CampaignWorker.jobs.should be_empty
        campaign.send_campaign!
        CampaignWorker.jobs.size.should == 10
      end
    end

    context 'with 100 queued mails' do
      before do
        queued_mails = 'Array'
        queued_mails.stub(:count).and_return(100)
        campaign.stub(:queued_mails).and_return(queued_mails)
      end

      it "enqueues 1 campaign worker jobs" do
        CampaignWorker.jobs.should be_empty
        campaign.send_campaign!
        CampaignWorker.jobs.size.should == 1
      end
    end

    context 'with 5 queued mails' do
      before do
        queued_mails = 'Array'
        queued_mails.stub(:count).and_return(5)
        campaign.stub(:queued_mails).and_return(queued_mails)
      end

      it "enqueues 1 campaign worker jobs" do
        CampaignWorker.jobs.should be_empty
        campaign.send_campaign!
        CampaignWorker.jobs.size.should == 1
      end
    end


  end




end
