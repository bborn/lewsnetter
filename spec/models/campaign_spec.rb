require 'spec_helper'

describe Campaign do
  let(:campaign) {
    campaign = FactoryGirl.create(:campaign)
  }

  describe "#queued!" do
    it "should notify admin" do
      campaign.update_attribute(:aasm_state, 'queueing')

      campaign.should_receive(:notify_admin_of_state_change){ true }

      campaign.queued!
    end

  end

  describe "#send_preview" do
    before(:each) do
      campaign.preview_recipients = 'foo@example.com, bar@example.com'
    end

    it 'should not change state' do
      expect {
        campaign.send_preview
      }.to_not change{ campaign.state }
    end

    it "should prefix the subject line" do
      campaign.send_preview
      email = ActionMailer::Base.deliveries.last
      email.subject.should == "[PREVIEW] #{campaign.subject}"
    end

  end

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
