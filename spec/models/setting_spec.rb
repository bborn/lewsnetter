require 'spec_helper'

describe Setting do

  describe '#get_with_default' do

    it "returns a default when no setting is found" do
      result = Setting.get_with_default('foo', 'bar')
      result.should == 'bar'
    end

    it "doesn't return the default when a setting is found" do
      Setting.stub(:get).with('foo').and_return("found")

      result = Setting.get_with_default('foo', 'bar')
      result.should == 'found'

    end

  end

end
