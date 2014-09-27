require 'spec_helper'

describe "mailing_lists/index" do
  before(:each) do
    assign(:mailing_lists, [
      stub_model(MailingList),
      stub_model(MailingList)
    ])
  end

  it "renders a list of mailing_lists" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
