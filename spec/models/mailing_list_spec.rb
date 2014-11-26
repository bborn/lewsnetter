require 'spec_helper'

describe MailingList do

  describe "#import_rows" do
    let(:subscription) {
      sub = FactoryGirl.create(:subscription, email: 'foo@bar.com')
      sub.subscribed = false
      sub.mailing_lists << FactoryGirl.create(:mailing_list)
      sub.save!
      sub
    }


    it "should not change subscribed state of existing subscription" do
      mailing_list = subscription.mailing_lists.first

      subscription.subscribed.should == false

      rows = [
        {email: subscription.email, name: 'John Doe'}
      ]

      expect {
        mailing_list.import_rows rows
      }.to_not change(subscription, :subscribed)

    end

  end


end
