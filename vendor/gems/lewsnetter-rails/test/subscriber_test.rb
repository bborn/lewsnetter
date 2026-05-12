require "test_helper"

# Minimal stand-in for an ActiveRecord-style class. We only need the public
# surface that `acts_as_lewsnetter_subscriber` touches (after_commit + the
# attribute readers), so we shim the callback hook by storing the trigger.
class FakeUser
  extend Lewsnetter::Subscriber::ClassMethods

  class << self
    attr_accessor :registered_callbacks

    def after_commit(method_name, on: nil)
      self.registered_callbacks ||= []
      self.registered_callbacks << {method: method_name, on: on}
    end
  end

  attr_accessor :id, :email, :full_name, :plan_tier

  def initialize(id:, email:, full_name: nil, plan_tier: "free")
    @id = id
    @email = email
    @full_name = full_name
    @plan_tier = plan_tier
  end
end

class SubscriberTest < Minitest::Test
  def setup
    setup_default_config
    Lewsnetter.configuration.async = true
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    FakeUser.registered_callbacks = nil
    FakeUser.acts_as_lewsnetter_subscriber(
      external_id: :id,
      email: :email,
      name: :full_name,
      attributes: ->(u) { {plan: u.plan_tier} }
    )
  end

  def test_registers_after_commit_callbacks
    methods = FakeUser.registered_callbacks.map { |c| c[:method] }
    assert_includes methods, :sync_to_lewsnetter!
    assert_includes methods, :delete_from_lewsnetter!
  end

  def test_payload_uses_config
    user = FakeUser.new(id: 7, email: "a@example.com", full_name: "Alice", plan_tier: "growth")
    payload = user.lewsnetter_payload
    assert_equal "7", payload[:external_id]
    assert_equal "a@example.com", payload[:email]
    assert_equal "Alice", payload[:name]
    assert_equal({plan: "growth"}, payload[:attributes])
  end

  def test_sync_enqueues_when_async
    user = FakeUser.new(id: 7, email: "a@example.com", full_name: "Alice")
    user.sync_to_lewsnetter!
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal 1, enqueued.length
    assert_equal "Lewsnetter::SyncJob", enqueued.first[:job].name
    payload = enqueued.first[:args].first
    assert_equal "7", payload[:external_id] || payload["external_id"]
  end

  def test_delete_enqueues_when_async
    user = FakeUser.new(id: 7, email: "a@example.com")
    user.delete_from_lewsnetter!
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
    assert_equal 1, enqueued.length
    payload = enqueued.first[:args].first
    assert(payload[:_delete] || payload["_delete"])
  end

  def test_sync_runs_inline_when_async_false
    Lewsnetter.configuration.async = false
    FakeNetHttp.next_response = FakeResponse.new("200", "{}")
    user = FakeUser.new(id: 8, email: "b@example.com")
    user.sync_to_lewsnetter!
    req = FakeNetHttp.last_request
    refute_nil req
    assert_equal "/api/v1/teams/99/subscribers", req.path
  end
end
