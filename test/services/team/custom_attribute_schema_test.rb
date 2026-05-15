# frozen_string_literal: true

require "test_helper"

class Team
  class CustomAttributeSchemaTest < ActiveSupport::TestCase
    setup do
      @team = create(:team)
    end

    test "returns empty schema and zero sample_size for team with no subscribers" do
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal({}, result[:sample])
      assert_equal 0, result[:sample_size]
    end

    test "returns empty schema and zero sample_size when team is nil" do
      result = Team::CustomAttributeSchema.new(team: nil).call
      assert_equal({}, result[:sample])
      assert_equal 0, result[:sample_size]
    end

    test "infers boolean type" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"active" => true})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "boolean", result[:sample]["active"]
    end

    test "infers integer type" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"score" => 42})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "integer", result[:sample]["score"]
    end

    test "infers number type for floats" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"rating" => 4.5})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "number", result[:sample]["rating"]
    end

    test "infers array type" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"tags" => ["a", "b"]})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "array", result[:sample]["tags"]
    end

    test "infers object type" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"meta" => {"key" => "val"}})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "object", result[:sample]["meta"]
    end

    test "infers null type" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"missing" => nil})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "null", result[:sample]["missing"]
    end

    test "infers string type" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"city" => "Portland"})
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal "string", result[:sample]["city"]
    end

    test "joins multiple observed types with pipe separator" do
      @team.subscribers.create!(email: "a@ex.com", custom_attributes: {"flexible" => "text"})
      @team.subscribers.create!(email: "b@ex.com", custom_attributes: {"flexible" => 99})
      result = Team::CustomAttributeSchema.new(team: @team).call
      types = result[:sample]["flexible"].split("|").sort
      assert_equal %w[integer string], types
    end

    test "sample_size reflects number of rows sampled" do
      3.times.with_index { |i| @team.subscribers.create!(email: "s#{i}@ex.com", custom_attributes: {"n" => i}) }
      result = Team::CustomAttributeSchema.new(team: @team, limit: 2).call
      assert_equal 2, result[:sample_size]
    end

    test "ignores subscribers with empty custom_attributes" do
      @team.subscribers.create!(email: "empty@ex.com")  # default {}
      result = Team::CustomAttributeSchema.new(team: @team).call
      assert_equal({}, result[:sample])
      assert_equal 0, result[:sample_size]
    end
  end
end
