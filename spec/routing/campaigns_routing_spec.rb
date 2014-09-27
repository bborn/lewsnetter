require "spec_helper"

describe CampaignsController do
  describe "routing" do

    it "routes to #index" do
      get("/campaigns").should route_to("campaigns#index")
    end

    it "routes to #new" do
      get("/campaigns/new").should route_to("campaigns#new")
    end

    it "routes to #show" do
      get("/campaigns/1").should route_to("campaigns#show", :id => "1")
    end

    it "routes to #edit" do
      get("/campaigns/1/edit").should route_to("campaigns#edit", :id => "1")
    end

    it "routes to #create" do
      post("/campaigns").should route_to("campaigns#create")
    end

    it "routes to #update" do
      put("/campaigns/1").should route_to("campaigns#update", :id => "1")
    end

    it "routes to #destroy" do
      delete("/campaigns/1").should route_to("campaigns#destroy", :id => "1")
    end

  end
end
