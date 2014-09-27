require 'spec_helper'

describe "campaigns/edit" do
  before(:each) do
    @campaign = assign(:campaign, stub_model(Campaign))
  end

  it "renders the edit campaign form" do
    render

    # Run the generator again with the --webrat flag if you want to use webrat matchers
    assert_select "form[action=?][method=?]", campaign_path(@campaign), "post" do
    end
  end
end
