# frozen_string_literal: true

require "test_helper"

module Mcp
  module Tools
    module Team
      class ListCompaniesTest < ActiveSupport::TestCase
        setup do
          @user = create(:onboarded_user)
          @team = @user.current_team
          @ctx = Mcp::Tool::Context.new(user: @user, team: @team)
          @other_team = create(:team)

          @c1 = @team.companies.create!(name: "Acme Corp", external_id: "acme-001")
          @c2 = @team.companies.create!(name: "Beta LLC", external_id: "beta-002", custom_attributes: {"industry" => "tech"})
          @other = @other_team.companies.create!(name: "Other Co")
        end

        test "lists team's companies with correct total and pagination defaults" do
          result = ListCompanies.new.invoke(arguments: {}, context: @ctx)
          ids = result[:companies].map { |h| h[:id] }
          assert_includes ids, @c1.id
          assert_includes ids, @c2.id
          refute_includes ids, @other.id
          assert_equal 2, result[:total]
          assert_equal 50, result[:limit]
          assert_equal 0, result[:offset]
        end

        test "serializes expected fields" do
          result = ListCompanies.new.invoke(arguments: {}, context: @ctx)
          company = result[:companies].find { |h| h[:id] == @c2.id }
          assert_equal "Beta LLC", company[:name]
          assert_equal "beta-002", company[:external_id]
          assert_equal({"industry" => "tech"}, company[:custom_attributes])
          assert_equal 0, company[:subscriber_count]
          assert_match(/\d{4}-\d{2}-\d{2}T/, company[:created_at])
          assert_match(/\d{4}-\d{2}-\d{2}T/, company[:updated_at])
        end

        test "query matches name substring" do
          result = ListCompanies.new.invoke(arguments: {"query" => "Acme"}, context: @ctx)
          assert_equal [@c1.id], result[:companies].map { |h| h[:id] }
          assert_equal 1, result[:total]
        end

        test "query matches external_id substring" do
          result = ListCompanies.new.invoke(arguments: {"query" => "beta"}, context: @ctx)
          assert_equal [@c2.id], result[:companies].map { |h| h[:id] }
        end

        test "query is case-insensitive (LIKE)" do
          result = ListCompanies.new.invoke(arguments: {"query" => "acme"}, context: @ctx)
          assert_equal 1, result[:total]
        end

        test "pagination via limit and offset" do
          result = ListCompanies.new.invoke(arguments: {"limit" => 1, "offset" => 1}, context: @ctx)
          assert_equal 1, result[:companies].length
          assert_equal 2, result[:total]
          assert_equal 1, result[:limit]
          assert_equal 1, result[:offset]
        end

        test "other team's company is not visible" do
          result = ListCompanies.new.invoke(arguments: {}, context: @ctx)
          ids = result[:companies].map { |h| h[:id] }
          refute_includes ids, @other.id
        end

        test "subscriber_count reflects associated subscribers" do
          sub = @team.subscribers.create!(email: "user@acme.com")
          sub.update!(company: @c1)
          result = ListCompanies.new.invoke(arguments: {"query" => "Acme"}, context: @ctx)
          company = result[:companies].first
          assert_equal 1, company[:subscriber_count]
        end

        test "metadata is wired" do
          assert_equal "team_list_companies", ListCompanies.tool_name
          assert_match(/compan/i, ListCompanies.description)
        end
      end
    end
  end
end
