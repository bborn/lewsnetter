require 'spec_helper'

describe QueuedMail do
  let(:campaign) { FactoryGirl.create(:campaign) }
  let(:queued_mail) {
    sub = FactoryGirl.create(:subscription)
    sub.mailing_lists << campaign.mailing_list

    queued_mail = campaign.queued_mails.create(:to => sub.email)
    queued_mail = QueuedMail.find queued_mail.id
    queued_mail
  }

  describe "#deliver" do

    it "puts queued_mail back in the queue if mail#deliver fails" do
      mail = mock('Mail')
      mail.stub(:deliver){ raise 'Poop' }

      queued_mail.stub(:construct_mail).and_return(mail)
      queued_mail.deliver

      QueuedMail.count.should == 1
    end

    it "puts queued_mail into deliveries if mail#deliver succeeds" do
      queued_mail.deliver
      QueuedMail.count.should == 0
      Delivery.count.should == 1
    end

    it "will not send the same mail twice" do
      queued_mail.deliver

      #this mail is now sent
      Delivery.count.should == 1
      QueuedMail.count.should == 0

      #duplicate queued_mail
      new_queued_mail = QueuedMail.create(queued_mail.attributes)
      QueuedMail.count.should == 1

      new_queued_mail.deliver

      #this duplicate should not send.
      Delivery.count.should == 1
      QueuedMail.count.should == 0

    end

  end

end
