require 'spec_helper'

describe MailingList do

  describe "#import" do

    before(:each) do
      @mailing_list = FactoryGirl.create(:mailing_list)
      @fixture_path = 'spec/fixtures'
    end

    it "should import a CSV file" do
      file =  File.open("#{@fixture_path}/import.csv",  "r:bom|utf-8")
      res  = @mailing_list.import file

      assert_equal res[:key_mapping], {:name=>:name, :email=>:email, :created_at=>:created_at}
      assert_equal res[:status], :ok
    end

    it "should import a CSV file with non standard headers" do
      file  = File.open("#{@fixture_path}/nonstandard-headers.csv",  "r:bom|utf-8")
      res   = @mailing_list.import file

      assert_equal res[:key_mapping], {:firstname=>:name, :"e-mail"=>:email, :subscribed=>:created_at}
      assert_equal res[:status], :ok
    end

    it "should not import a CSV file with no email header" do
      file =  File.open("#{@fixture_path}/no-email-header.csv",  "r:bom|utf-8")
      res = @mailing_list.import(file)

      assert_equal res[:status], :error
    end

  end

  describe "#import_row" do

    it "should handle letter accents" do
      mailing_list = FactoryGirl.create(:mailing_list)
      row = {
          name: "Froğdu Tester",
          email: "Çağ@example.com",
          created_at: "2015-01-12 11:21 AM"
        }

      mailing_list.import_row row
    end
  end

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
