# Self-hosting Lewsnetter

The hosted version at app.lewsnetter.dev costs $10/month per team and just works. Self-hosting costs at least that in time + ops — you're trading dollars for control.

**Choose self-host if:**
- You want full code control (security audit, custom features, integrate with internal systems)
- You have strong opinions about infra (a server you already run, specific region, your own backup strategy)
- You're philosophically committed to running your own software
- You're a Rails shop and modifying the source is your superpower

**Use the hosted version if:**
- You just want it to work
- $10/month is less than your time

OK, you're self-hosting. Here's the walkthrough.

## Architecture

```
            ┌─────────────────────────┐
            │  Cloudflare (proxy)     │  Orange-cloud + Full (Strict) SSL
            └────────────┬────────────┘
                         │ TLS via Origin CA cert
            ┌────────────▼────────────┐
            │  kamal-proxy (Hetzner)  │  TLS terminator + routing
            │  Hostnames:             │
            │   - app.example.com     │
            │   - email.tenant.com    │
            └────────────┬────────────┘
                         │
            ┌────────────▼────────────┐
            │  Rails 8 (Puma :3000)   │  Web role
            │  Solid Queue worker     │  Background jobs
            │  Litestream replicator  │  → R2 backup every few sec
            └────────────┬────────────┘
                         │
            ┌────────────▼────────────┐
            │  SQLite on local disk   │  /rails/storage (named volume)
            └─────────────────────────┘
```

Two container roles off one image: `web` and `worker`. SQLite on a Docker named volume. Litestream streams the DB files to Cloudflare R2 (or any S3-compatible target) so you can recover from a server loss.

## Prerequisites

| | What | Notes |
|---|---|---|
| **Server** | Hetzner CPX21 (~$8/mo) | 1-CPU/2GB is fine for low-traffic. Bump up for heavy lists. |
| **Domain** | Anything you control | You'll point it at the server's IP. |
| **Cloudflare** | Free account | Used as proxy + Origin CA cert authority. |
| **GHCR or Docker registry** | GitHub Container Registry works | Kamal pushes images here. |
| **Backup target** | Cloudflare R2 (recommended) | Litestream supports S3, GCS, ABS, SFTP too. |
| **AWS** | An SES account | The product needs this to send. |

## Step 1: Provision the server + DNS

```sh
# Hetzner Cloud → create a CPX21 in your region
# SSH in once, set up a non-root user (kamal will work as root over SSH)
```

Point your domain (or subdomain) at the server's IP via your DNS provider. If you're using Cloudflare DNS, set the proxy to "orange cloud" (proxied) for TLS termination.

## Step 2: Cloudflare zone + Origin CA cert

1. Add your domain to Cloudflare. Update nameservers at your registrar.
2. SSL/TLS → **Full (Strict)**.
3. SSL/TLS → Origin Server → **Create Certificate** for `*.example.com, example.com`. Save the cert + key — you'll paste them into `.kamal/secrets` in step 4.

## Step 3: Fork + clone

```sh
git clone https://github.com/bborn/lewsnetter.git
cd lewsnetter
```

Or fork on GitHub and clone your fork — you'll probably want to commit your own marketing copy / branding.

## Step 4: Create `.kamal/secrets`

The file format + every required variable is documented in [`config/deploy.yml`](../config/deploy.yml). Quick start:

```sh
cat > .kamal/secrets <<'EOF'
KAMAL_REGISTRY_PASSWORD=$(gh auth token)
RAILS_MASTER_KEY=$(cat config/master.key)

LITESTREAM_REPLICA_ACCESS_KEY_ID=<r2-access-key>
LITESTREAM_REPLICA_SECRET_ACCESS_KEY=<r2-secret-key>

STRIPE_PUBLISHABLE_KEY=<your-stripe-pk>      # only if you enable billing
STRIPE_SECRET_KEY=<your-stripe-sk>
STRIPE_WEBHOOKS_ENDPOINT_SECRET=<your-stripe-whsec>

ORIGIN_CERT='-----BEGIN CERTIFICATE-----
... (Cloudflare Origin CA cert, multi-line, in quotes)
-----END CERTIFICATE-----'

ORIGIN_KEY='-----BEGIN PRIVATE KEY-----
... (Cloudflare Origin CA key, multi-line, in quotes)
-----END PRIVATE KEY-----'
EOF
chmod 600 .kamal/secrets
```

## Step 5: Edit `config/deploy.yml`

The shipped config is for the hosted Lewsnetter deployment. You'll want to change:
- `servers.web.hosts` and `servers.worker.hosts` → your server's IP
- `proxy.hosts` → your domain(s)
- `env.clear.BASE_URL` → your app URL
- `env.clear.APP_BASE_URL` → same as BASE_URL (unless you split marketing + app onto two subdomains like the hosted version does)
- `env.clear.LEWSNETTER_LEGAL_EMAIL` + `LEWSNETTER_ABUSE_EMAIL` → real mailboxes you check
- `env.clear.LITESTREAM_REPLICA_*` → your R2 / S3 bucket details
- `registry.username` → your GHCR (or other) username

## Step 6: Deploy

```sh
bundle exec kamal setup    # first run only — installs Docker, builds + pushes image, starts containers
```

About 5-15 minutes later, your app is live at https://your-domain.com. The first user to sign up is auto-promoted to admin.

Subsequent deploys:

```sh
bundle exec kamal deploy
```

## Step 7 (optional): CI deploys via GitHub Actions

There's a workflow at [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml). It expects these GitHub Actions secrets:
- `SSH_PRIVATE_KEY` — for connecting to your server
- `SERVER_HOST` — server IP
- `RAILS_MASTER_KEY`
- `ORIGIN_CERT` + `ORIGIN_KEY`
- `LITESTREAM_REPLICA_ACCESS_KEY_ID` + `_SECRET_ACCESS_KEY`
- `STRIPE_PUBLISHABLE_KEY` + `_SECRET_KEY` + `_WEBHOOKS_ENDPOINT_SECRET` (only if you enable billing)

Add those, push to master, and CI redeploys on every commit.

## Common gotchas

**SSL handshake failed (Cloudflare error 525).**
The Origin CA cert in `.kamal/secrets` doesn't match the hostname Cloudflare is sending. Confirm the cert SANs cover the hostname (`openssl x509 -in cert.pem -text | grep DNS`) and that kamal-proxy is using the right cert (`kamal app logs`).

**Litestream isn't replicating.**
Check `kamal app logs | grep litestream`. Usually one of: R2 credentials wrong, bucket doesn't exist, or `litestream.yml` config path is wrong. The replica section in `config/litestream.yml` should reference each SQLite file by absolute path.

**Database lost on container restart.**
Make sure `volumes:` in `config/deploy.yml` mounts `lewsnetter_storage:/rails/storage`. SQLite files live at `/rails/storage/lewsnetter_production*.sqlite3`.

**The marketing site and app are on the same host but I get a redirect loop.**
The hosted Lewsnetter splits `lewsnetter.dev` (marketing) and `app.lewsnetter.dev` (app). If you're running a single-host deployment, leave `APP_BASE_URL` env var unset — the marketing helpers will resolve same-host and skip cross-host redirects.

## Backups + restore

Litestream streams every SQLite write to R2 within seconds. To restore:

```sh
litestream restore -config /etc/litestream.yml /rails/storage/lewsnetter_production.sqlite3
```

Test this BEFORE you need it. Spin up a second server, restore from R2, verify the restored DB opens cleanly.

## Updates

```sh
git pull
bundle exec kamal deploy
```

Migrations run automatically as part of the deploy. Roll back with `kamal rollback` if something goes wrong; SQLite + Litestream means you can also restore to a point-in-time if you really need to.

## Hardening checklist (skip at your own risk)

- [ ] Devise confirmable on new signups (currently optional)
- [ ] Rack-attack rate limits on auth endpoints
- [ ] Sentry / error tracking
- [ ] Off-host log shipping (Loki, Datadog, etc.)
- [ ] Server-side fail2ban for SSH
- [ ] Restrict GHCR registry push tokens to read-only on the server
- [ ] Rotate the `RAILS_MASTER_KEY` if it ever lands in chat / Slack / a screenshot

## I'm stuck

Read the source. The Kamal config is heavily commented; the Rails app follows BulletTrain conventions; the SES integration is in `app/services/ses/`. If you find a real bug, open an issue.
