require "minitest/autorun"
require "yaml"

# litestream.yml is the only backup policy production has. Litestream 0.3
# defaults retention to 24h and deletes whole generations that fall outside
# it, which leaves about a day to notice a bad write or a dropped table.
class LitestreamConfigTest < Minitest::Test
  CONFIG = YAML.safe_load_file(File.expand_path("../litestream.yml", __dir__))
  DATABASES = %w[
    /rails/storage/lewsnetter_production.sqlite3
    /rails/storage/lewsnetter_production_queue.sqlite3
    /rails/storage/lewsnetter_production_cable.sqlite3
  ].freeze
  MINIMUM_RETENTION_HOURS = 72

  def test_every_production_database_is_replicated
    assert_equal DATABASES.sort, CONFIG.fetch("dbs").map { |db| db.fetch("path") }.sort
  end

  def test_every_replica_keeps_at_least_three_days
    each_replica do |path, replica|
      retention = replica["retention"]
      refute_nil retention, "#{path}: no retention set, so Litestream's 24h default applies"
      assert_operator hours(retention), :>=, MINIMUM_RETENTION_HOURS, "#{path}: retention #{retention} is too short"
    end
  end

  def test_every_replica_takes_a_daily_snapshot
    each_replica do |path, replica|
      interval = replica["snapshot-interval"]
      refute_nil interval, "#{path}: no snapshot-interval set"
      assert_operator hours(interval), :<=, 24, "#{path}: snapshot-interval #{interval} is longer than a day"
    end
  end

  private

  def each_replica
    CONFIG.fetch("dbs").each do |db|
      db.fetch("replicas").each { |replica| yield db.fetch("path"), replica }
    end
  end

  def hours(duration)
    match = duration.to_s.match(/\A(\d+)([hm])\z/) or flunk("unparseable duration #{duration.inspect}")
    value = match[1].to_i
    (match[2] == "h") ? value : value / 60.0
  end
end
