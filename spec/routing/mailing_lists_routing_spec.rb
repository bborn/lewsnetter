require "spec_helper"

describe MailingListsController do
  describe "routing" do

    it "routes to #index" do
      get("/mailing_lists").should route_to("mailing_lists#index")
    end

    it "routes to #new" do
      get("/mailing_lists/new").should route_to("mailing_lists#new")
    end

    it "routes to #show" do
      get("/mailing_lists/1").should route_to("mailing_lists#show", :id => "1")
    end

    it "routes to #edit" do
      get("/mailing_lists/1/edit").should route_to("mailing_lists#edit", :id => "1")
    end

    it "routes to #create" do
      post("/mailing_lists").should route_to("mailing_lists#create")
    end

    it "routes to #update" do
      put("/mailing_lists/1").should route_to("mailing_lists#update", :id => "1")
    end

    it "routes to #destroy" do
      delete("/mailing_lists/1").should route_to("mailing_lists#destroy", :id => "1")
    end

  end
end
