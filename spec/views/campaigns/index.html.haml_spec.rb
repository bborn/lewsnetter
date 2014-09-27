require 'spec_helper'

describe "campaigns/index" do
  before(:each) do
    assign(:campaigns, [
      stub_model(Campaign),
      stub_model(Campaign)
    ])
  end

  it "renders a list of campaigns" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
