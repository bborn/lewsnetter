# Lewsnetter v2 — Deploy

**Status:** Scaffolded 2026-05-12. Server provisioned, Kamal config in place, *not yet deployed* (waiting on Cloudflare R2 + GitHub Actions secrets from Bruno).

## Architecture

One Hetzner box, three containers, one named volume.

```
                       ┌────────────────────────────────────────┐
                       │  Hetzner CPX21 — lewsnetter-app1       │
                       │  Location: ash (Ashburn, VA, us-east)  │
                       │  IPv4: 178.156.185.100                 │
                       │  IPv6: 2a01:4ff:f0:b59d::1             │
                       │                                        │
   GHCR ──pulls──▶     │  ┌──── lewsnetter-web (Puma :3000)──┐  │
   ghcr.io/bborn       │  │  Rails 8 + Litestream replicator │  │
   /lewsnetter         │  │  + Solid Cable (subscription)    │  │
                       │  └──────────────────────────────────┘  │
                       │  ┌──── lewsnetter-worker ──────────┐   │
                       │  │  bundle exec rake              │   │
                       │  │    solid_queue:start            │   │
                       │  └─────────────────────────────────┘   │
                       │  ┌──── Kamal proxy (Traefik) ─────┐    │
                       │  │  TLS via Let's Encrypt          │    │
                       │  │  Routes :443 → web :3000        │    │
                       │  └─────────────────────────────────┘    │
                       │                                        │
                       │  Named volume: lewsnetter_storage      │
                       │  /rails/storage/lewsnetter_production*  │
                       │  .sqlite3   (primary / queue / cable)   │
                       └────────────────────┬───────────────────┘
                                            │
                                            ▼  Litestream WAL stream
                       Cloudflare R2 (S3-compat) — bucket `lewsnetter-litestream`
                         primary/  queue/  cable/   ← snapshots + WAL segments
```

### Why this shape

- **Single box** is fine for the foreseeable future. Bullet Train + SQLite + Solid Queue on a 3-vCPU / 4GB box runs more than enough campaigns for tenant zero (IK), tenant one (Wovenmade), and a handful of paying users beyond.
- **SQLite + Litestream** means the box is disposable. If we wipe the server, `bin/docker-entrypoint` runs `litestream restore` against each DB on boot and pulls the latest snapshot back from R2.
- **Ashburn (us-east)** colocates with the default SES region (`us-east-1`), so SES SendBulkEmail round-trips are sub-10ms.
- **Kamal 2 + Traefik** for TLS keeps us on the path of least surprise — no nginx config, no Cloudflare Worker, just Let's Encrypt HTTP-01.

## Inventory

| Resource | Value |
|---|---|
| Hetzner server name | `lewsnetter-app1` |
| Hetzner server ID | `130640866` |
| Server type | `cpx21` (2 shared vCPU × AMD, 4 GB RAM, 80 GB SSD) |
| Location | `ash` (Ashburn, VA — us-east) |
| Image | `ubuntu-24.04` |
| Public IPv4 | `178.156.185.100` |
| Public IPv6 | `2a01:4ff:f0:b59d::1` |
| Monthly cost | ~$8.90 / month (cpx21 in ash, current pricing) |
| SSH key in Hetzner | `lewsnetter-deploy` (ID 112196927) |

> **Note on server sizing.** The task spec called for `cx22`, but Hetzner has phased that SKU out — the CLI returns "Server Type not found". The closest equivalent in `ash` is `cpx21` (3 shared vCPU AMD, 4 GB RAM, 80 GB SSD), which is what's actually running. If you want to downsize to the cheapest-possible box, swap to `cpx11` (2 vCPU, 2 GB RAM, 40 GB SSD) — but Bullet Train + Solid Queue worker on 2 GB will be tight.

## Secrets matrix

Where each secret lives, and who needs it.

| Secret | Local (Bruno's laptop) | CI (GitHub Actions) | Container runtime |
|---|---|---|---|
| Hetzner API token | `~/.config/hcloud/cli.toml` | — | — |
| SSH deploy private key | `~/.ssh/lewsnetter_deploy` (mode 600) | `SSH_PRIVATE_KEY` repo secret | — |
| SSH deploy public key | `~/.ssh/lewsnetter_deploy.pub`, also installed on the server via Hetzner cloud-init | — | — |
| Rails master key | `config/master.key` (gitignored) | `RAILS_MASTER_KEY` repo secret | `RAILS_MASTER_KEY` env (via Kamal `env.secret`) |
| `secret_key_base` | inside encrypted `config/credentials.yml.enc` | — | derived at boot via `RAILS_MASTER_KEY` |
| ActiveRecord encryption keys | inside encrypted `config/credentials.yml.enc` | — | derived at boot |
| Cloudflare R2 access key ID | env var when running `kamal deploy` locally | `LITESTREAM_REPLICA_ACCESS_KEY_ID` repo secret | `LITESTREAM_REPLICA_ACCESS_KEY_ID` env |
| Cloudflare R2 secret access key | env var when running `kamal deploy` locally | `LITESTREAM_REPLICA_SECRET_ACCESS_KEY` repo secret | `LITESTREAM_REPLICA_SECRET_ACCESS_KEY` env |
| Hetzner server IP | hard-coded in `config/deploy.yml` | `SERVER_HOST` repo secret (for ssh-keyscan) | — |
| GHCR pull token | `gh auth token` on laptop, `GITHUB_TOKEN` in CI | `GITHUB_TOKEN` (auto-provided) | `KAMAL_REGISTRY_PASSWORD` env |
| Per-tenant AWS SES keys | — | — | encrypted in `Team::SesConfiguration` rows via Rails `encrypts` (uses ActiveRecord encryption keys above) |

### What `config/master.key` decrypts

The encrypted `config/credentials.yml.enc` currently holds:
- `secret_key_base` — Rails session signing
- `active_record_encryption.{primary_key, deterministic_key, key_derivation_salt}` — for `encrypts :attr` columns. Per-tenant SES credentials in `Team::SesConfiguration` use these.
- `cloudflare.r2.*` — placeholder fields, only populated if/when we move Active Storage onto R2. Litestream itself uses the Kamal env vars instead.

## What's still needed from Bruno before first deploy

The scaffold is complete, but the deploy itself can't run until these are in place:

### 1. Create the Cloudflare R2 bucket

In the Cloudflare dashboard:
1. R2 → Create bucket → name it `lewsnetter-litestream`. Region/location: leave default (auto).
2. Note your Cloudflare account ID — visible in the R2 sidebar URL or on the R2 overview page.
3. Update `config/deploy.yml`:
   - Replace `CLOUDFLARE_R2_ACCOUNT_ID` in the `LITESTREAM_REPLICA_ENDPOINT` value with your account ID.
4. R2 → Manage API Tokens → Create API Token → permissions: Object Read & Write, scoped to the `lewsnetter-litestream` bucket.
5. Save the resulting Access Key ID + Secret Access Key — these are the `LITESTREAM_REPLICA_*` values below.

### 2. Create the DNS record

Cloudflare DNS for `whinynil.co`:
- A record: `lewsnetter` → `178.156.185.100`
- TTL: Auto
- **Proxy status: DNS only (gray cloud)** for the first deploy. Let's Encrypt HTTP-01 validation needs unproxied access to port 80.
- After the cert is issued and stable, you can optionally flip to Proxied (orange cloud) and switch `proxy.ssl: false` in `config/deploy.yml` to have Cloudflare handle SSL termination instead.

### 3. Add GitHub Actions secrets

Repo: https://github.com/bborn/lewsnetter/settings/secrets/actions

| Secret name | Value |
|---|---|
| `SSH_PRIVATE_KEY` | Contents of `~/.ssh/lewsnetter_deploy` (include the `-----BEGIN OPENSSH PRIVATE KEY-----` headers). Run `cat ~/.ssh/lewsnetter_deploy \| pbcopy` to grab it. |
| `SERVER_HOST` | `178.156.185.100` |
| `RAILS_MASTER_KEY` | Contents of `config/master.key`. Run `cat config/master.key \| pbcopy`. |
| `LITESTREAM_REPLICA_ACCESS_KEY_ID` | From step 1 |
| `LITESTREAM_REPLICA_SECRET_ACCESS_KEY` | From step 1 |

### 4. (Optional) Verify locally before pushing

```sh
export LITESTREAM_REPLICA_ACCESS_KEY_ID=...
export LITESTREAM_REPLICA_SECRET_ACCESS_KEY=...
mise x -- bundle exec kamal setup
```

`kamal setup` installs Docker on the box (via Kamal's bootstrap), pushes the first image to GHCR, and runs the initial container. After it returns clean:

```sh
curl -I https://lewsnetter.whinynil.co/up
# expect HTTP/2 200
```

### 5. From here on out

Every push to `master` runs `.github/workflows/deploy.yml`: tests → build → push to GHCR → `kamal deploy`. Rolling restart, no downtime.

## Litestream — restore on box-rebuild

The web container's entrypoint (`bin/docker-entrypoint`) runs:

```bash
litestream restore -if-replica-exists -config /etc/litestream.yml /rails/storage/lewsnetter_production.sqlite3
litestream restore -if-replica-exists -config /etc/litestream.yml /rails/storage/lewsnetter_production_queue.sqlite3
litestream restore -if-replica-exists -config /etc/litestream.yml /rails/storage/lewsnetter_production_cable.sqlite3
```

on every cold start. If the local SQLite file is missing (fresh server, blown-away volume, etc.), it pulls the latest snapshot from R2; if the file is already present, it's a no-op. Then it wraps `bin/rails server` in `litestream replicate -exec` so the replicator runs alongside Puma and shares its lifecycle.

The worker container does not run `litestream replicate` — there's only one replicator per database, and the web role owns it.

## Open items / known gaps (not blocking the first deploy)

- The deploy workflow runs a **scoped** test suite (`test/services`, `test/jobs`, `test/controllers/account`) rather than the full BulletTrain scaffolded suite. Several BulletTrain stock controller tests fail today on this clean-slated v2 repo. Widen back to `bin/rails test` once those are triaged.
- No Honeybadger / Sentry wiring yet — the `Gemfile` has them commented out under `:production`. Add when error-rate visibility actually matters.
- No CloudWatch / external uptime monitoring. For the MVP, the GHA workflow run is the canary; promote to a real status check (UptimeRobot, BetterStack) after first paying customer.
- The Solid Queue worker shares the same volume as web (via Kamal's `volumes:`). Good — both containers see the same `/rails/storage`. If we ever scale to two app servers, we'll need a different replication story for `lewsnetter_production_queue.sqlite3` (probably a managed Postgres queue at that point).
- `secret_key_base` is freshly generated and stored in credentials. If we ever leak `config/master.key`, rotate by editing credentials + invalidating all existing sessions.

## Verifying the kamal setup attempt from this scaffold session

`kamal server bootstrap` was run after the scaffold and **succeeded** — Docker 29.4.3 is installed on `lewsnetter-app1` and the `kamal` network is created. `ssh -i ~/.ssh/lewsnetter_deploy root@178.156.185.100 "docker --version"` confirms.

`kamal proxy boot` failed at the GHCR login step with `Error response from daemon: Get "https://ghcr.io/v2/": denied: denied`. This is expected: no image has been pushed to `ghcr.io/bborn/lewsnetter` yet, and GHCR's docker registry returns `denied` for pulls against nonexistent repositories. The proxy itself uses `basecamp/kamal-proxy` from Docker Hub (no auth), but Kamal performs the registry login as part of its preflight before any operation. The first real `kamal deploy` will create the GHCR repo on push, and the proxy boot embedded in `kamal setup` will succeed on the next attempt.

**Net status:** Server provisioned, SSH verified, Docker installed, deploy config in place. Awaiting Bruno's R2 credentials + GitHub Actions secrets to complete first deploy.
