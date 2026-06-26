# One-time, idempotent backfills run on web boot — see bin/docker-entrypoint.
#
# These were previously two or three separate `bin/rails` invocations in the
# entrypoint, each paying the full ~6-8s Rails boot cost and delaying Puma past
# the kamal-proxy health-check window. Wrapping them in a single Rake task lets
# the entrypoint run `db:prepare app:boot_backfills` in ONE Rails process.
namespace :app do
  desc "Idempotent web-boot backfills: seed model registry + encrypt subscribers"
  task boot_backfills: :environment do
    # Seed the ruby_llm Model registry on first boot only. load_models is
    # idempotent (find-or-create per entry) but iterates the whole registry,
    # so gate on an empty table to keep subsequent restarts fast.
    Rake::Task["ruby_llm:load_models"].invoke if Model.count.zero?

    # Upgrade any plaintext subscriber email/name rows to encrypted storage.
    # Idempotent — returns fast when there's nothing left to upgrade.
    Rake::Task["subscribers:encrypt_at_rest"].invoke
  end
end
