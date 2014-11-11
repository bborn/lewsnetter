require "spec_helper"

describe UserMailer do
  # http://guides.rubyonrails.org/action_mailer_basics.html#mailer-testing
  describe "#campaign_notification" do
    let!(:campaign) {
      campaign  = FactoryGirl.create(:campaign)
    }
    let!(:user){
      user      = FactoryGirl.create(:user)
      user.is_admin = true
      user.save!
      user
    }

    it "should send" do
      expect {
        UserMailer.campaign_notification(campaign).deliver
      }.to change{ ActionMailer::Base.deliveries.count }.by(1)
    end


  end

end
