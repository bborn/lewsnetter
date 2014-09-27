require 'spec_helper'

describe "templates/index" do
  before(:each) do
    assign(:templates, [
      stub_model(Template),
      stub_model(Template)
    ])
  end

  it "renders a list of templates" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
