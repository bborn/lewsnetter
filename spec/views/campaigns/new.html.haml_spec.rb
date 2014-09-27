require 'spec_helper'

describe "campaigns/new" do
  before(:each) do
    assign(:campaign, stub_model(Campaign).as_new_record)
  end

  it "renders new campaign form" do
    render

    # Run the generator again with the --webrat flag if you want to use webrat matchers
    assert_select "form[action=?][method=?]", campaigns_path, "post" do
    end
  end
end
