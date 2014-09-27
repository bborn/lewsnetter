require 'spec_helper'

describe "Templates" do
  describe "GET /templates" do
    it "works! (now write some real specs)" do
      # Run the generator again with the --webrat flag if you want to use webrat methods/matchers
      get templates_path
      response.status.should be(200)
    end
  end
end
