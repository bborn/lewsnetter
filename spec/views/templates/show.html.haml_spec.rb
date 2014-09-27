require 'spec_helper'

describe "templates/show" do
  before(:each) do
    @template = assign(:template, stub_model(Template))
  end

  it "renders attributes in <p>" do
    render
    # Run the generator again with the --webrat flag if you want to use webrat matchers
  end
end
