require 'spec_helper'

describe "templates/edit" do
  before(:each) do
    @template = assign(:template, stub_model(Template))
  end

  it "renders the edit template form" do
    render

    # Run the generator again with the --webrat flag if you want to use webrat matchers
    assert_select "form[action=?][method=?]", template_path(@template), "post" do
    end
  end
end
