require 'spec_helper'

describe "campaigns/show" do
  before(:each) do
    @campaign = assign(:campaign, stub_model(Campaign))
  end

  it "renders attributes in <p>" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
