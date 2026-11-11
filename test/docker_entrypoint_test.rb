require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

# bin/docker-entrypoint decides whether production boots on the restored
# backup or on an empty database. These tests run the real script with
# `litestream` and `./bin/rails` replaced by stubs that log their arguments.
#
# The failure being guarded against: a restore error was swallowed
# (`|| true`), db:prepare built an empty schema, and `litestream replicate`
# shipped that empty database to R2 as the newest generation.
class DockerEntrypointTest < Minitest::Test
  ENTRYPOINT = File.expand_path("../bin/docker-entrypoint", __dir__)
  DATABASES = %w[lewsnetter_production lewsnetter_production_queue lewsnetter_production_cable].freeze
  WEB_CMD = ["./bin/rails", "server", "-p", "3000"].freeze
  WORKER_CMD = ["bundle", "exec", "rake", "solid_queue:start"].freeze

  def setup
    @dir = Dir.mktmpdir("entrypoint")
    @storage = File.join(@dir, "storage")
    @log = File.join(@dir, "calls.log")
    FileUtils.mkdir_p([@storage, File.join(@dir, "bin"), File.join(@dir, "stubs")])
    FileUtils.touch(@log)
    stub("bin/rails")
    stub("stubs/bundle")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_failed_restore_aborts_before_db_prepare_and_replicate
    stub("stubs/litestream", exit_status: 1)

    status = run_entrypoint(WEB_CMD)

    refute status.success?, "entrypoint must exit non-zero when a restore fails"
    refute_includes calls, "rails db:prepare app:boot_backfills"
    refute(calls.any? { |c| c.start_with?("litestream replicate") }, "must not start replicating")
  end

  def test_successful_restore_prepares_and_replicates
    stub("stubs/litestream", exit_status: 0, creates_restored_file: true)

    status = run_entrypoint(WEB_CMD)

    assert status.success?, "entrypoint failed: #{calls.inspect}"
    DATABASES.each do |db|
      assert_includes calls, "litestream restore -if-replica-exists -config /etc/litestream.yml #{@storage}/#{db}.sqlite3"
    end
    assert_includes calls, "rails db:prepare app:boot_backfills"
    assert(calls.last.start_with?("litestream replicate"), "web server must run under litestream replicate")
  end

  def test_existing_databases_are_not_restored
    stub("stubs/litestream", exit_status: 0)
    DATABASES.each { |db| FileUtils.touch(File.join(@storage, "#{db}.sqlite3")) }

    status = run_entrypoint(WEB_CMD)

    assert status.success?
    refute(calls.any? { |c| c.start_with?("litestream restore") })
  end

  def test_worker_does_not_restore_and_refuses_to_start_on_missing_database
    stub("stubs/litestream", exit_status: 0, creates_restored_file: true)

    status = run_entrypoint(WORKER_CMD)

    refute status.success?, "worker must not start before the web role has restored the databases"
    refute(calls.any? { |c| c.start_with?("litestream") }, "worker must not run litestream")
    refute(calls.any? { |c| c.start_with?("bundle") }, "worker command must not run")
  end

  def test_worker_starts_when_databases_exist
    stub("stubs/litestream", exit_status: 0)
    DATABASES.each { |db| FileUtils.touch(File.join(@storage, "#{db}.sqlite3")) }

    status = run_entrypoint(WORKER_CMD)

    assert status.success?
    assert_equal ["bundle exec rake solid_queue:start"], calls
  end

  private

  def run_entrypoint(cmd)
    env = {
      "PATH" => "#{File.join(@dir, "stubs")}:#{ENV.fetch("PATH")}",
      "LITESTREAM_REPLICA_BUCKET" => "test-bucket",
      "LEWSNETTER_STORAGE_DIR" => @storage,
      "CALL_LOG" => @log,
      "LD_PRELOAD" => ""
    }
    _out, _err, status = Open3.capture3(env, ENTRYPOINT, *cmd, chdir: @dir)
    status
  end

  def calls
    File.readlines(@log, chomp: true)
  end

  # Writes an executable that logs "<name> <args>" and exits with the given
  # status. `litestream replicate -exec` is logged too but not run.
  def stub(relative, exit_status: 0, creates_restored_file: false)
    path = File.join(@dir, relative)
    name = File.basename(relative)
    body = "#!/bin/bash\necho \"#{name} $*\" >> \"$CALL_LOG\"\n"
    if creates_restored_file
      body << "if [ \"$1\" = \"restore\" ]; then touch \"${@: -1}\"; fi\n"
    end
    body << "exit #{exit_status}\n"
    File.write(path, body)
    File.chmod(0o755, path)
  end
end
