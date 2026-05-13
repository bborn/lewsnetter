# SSL Full (Strict) Verification — Cloudflare → Hetzner origin

Task 3 from `PLAN-FOLLOWUPS.md`. We installed the Cloudflare Origin CA
certificate on `kamal-proxy` so the CF → origin leg is TLS, then handed off
to Bruno to flip the Cloudflare zone SSL mode from **Flexible** to
**Full (Strict)** in the dashboard.

## Mechanism — Option A (native Kamal `proxy.ssl.{certificate_pem,private_key_pem}`)

Kamal 2.11 ships with first-class support for custom TLS material on
kamal-proxy. We configure two secret keys in `config/deploy.yml`:

```yaml
proxy:
  ssl:
    certificate_pem: ORIGIN_CERT
    private_key_pem: ORIGIN_KEY
  ssl_redirect: false
  hosts:
    - lewsnetter.whinynil.co
    - email.influencekit.com
  forward_headers: true
  app_port: 3000
  healthcheck:
    path: /up
    interval: 20
```

`ORIGIN_CERT` and `ORIGIN_KEY` live in `.kamal/secrets` (gitignored,
mode 600). Each are multi-line PEM blobs wrapped in single quotes —
`Dotenv.parse` (used by Kamal::Secrets) handles them natively.

Why Option A over Option B (host bind-mount via pre-deploy hook):

- Zero custom shell scripts. Less to break, less to document.
- The cert is uploaded fresh on every deploy, so rotation = update
  `.kamal/secrets` + `kamal deploy`. No host SSH-and-replace dance.
- Matches Kamal/BulletTrain idioms: secrets via `.kamal/secrets`, no
  hardcoded paths in `config/deploy.yml`.

The relevant Kamal internals:

- `Kamal::Configuration::Proxy#custom_ssl_certificate?` — flips on
  when `ssl` is a hash with both PEM keys.
- `Kamal::Cli::App::SslCertificates#run` — runs before `App::Boot`
  on every `kamal deploy` / `kamal app boot`, calls `upload!` to
  drop the cert + key into the host TLS directory.
- The kamal-proxy container has
  `/root/.kamal/proxy/apps-config` bind-mounted to
  `/home/kamal-proxy/.apps-config`. Kamal writes to
  `.kamal/proxy/apps-config/lewsnetter/tls/web/{cert,key}.pem` and
  passes `--tls-certificate-path=/home/kamal-proxy/.apps-config/lewsnetter/tls/web/cert.pem`
  (and the matching `--tls-private-key-path`) to `kamal-proxy deploy`.
- `--tls-redirect="false"` because Cloudflare already does the
  edge redirect; during the Flexible→Full(Strict) flip the CF→origin
  leg may still be HTTP for a short window and we don't want a redirect
  loop. Once on Full (Strict) it's a no-op anyway.

## Deploy log evidence

From `kamal deploy` (commit-time deploy, finished in 54.6s):

```
INFO Writing SSL certificates for web on 178.156.185.100
INFO [7b42c799] Running /usr/bin/env mkdir -p .kamal/proxy/apps-config/lewsnetter/tls/web on 178.156.185.100
INFO Uploading .kamal/proxy/apps-config/lewsnetter/tls/web/cert.pem 100.0%
INFO Uploading .kamal/proxy/apps-config/lewsnetter/tls/web/key.pem 100.0%
...
INFO [4927b54b] Running docker exec kamal-proxy kamal-proxy deploy lewsnetter-web \
    --target="bfa26c52cfaa:3000" \
    --host="lewsnetter.whinynil.co" --host="email.influencekit.com" \
    --tls \
    --tls-certificate-path="/home/kamal-proxy/.apps-config/lewsnetter/tls/web/cert.pem" \
    --tls-private-key-path="/home/kamal-proxy/.apps-config/lewsnetter/tls/web/key.pem" \
    --tls-redirect="false" \
    --health-check-interval="20s" --health-check-path="/up" \
    --buffer-requests --buffer-responses --forward-headers \
    ...
INFO [4927b54b] Finished in 20.252 seconds with exit status 0 (successful).
INFO First web container is healthy on 178.156.185.100, booting any other roles
```

## Verification: origin presents the Origin CA cert

Direct TCP to the Hetzner box (bypasses Cloudflare):

```
$ echo | openssl s_client -connect 178.156.185.100:443 \
    -servername lewsnetter.whinynil.co 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

subject=O=CloudFlare, Inc., OU=CloudFlare Origin CA, CN=CloudFlare Origin Certificate
issuer=C=US, O=CloudFlare, Inc., OU=CloudFlare Origin SSL Certificate Authority, L=San Francisco, ST=California
notBefore=May 12 17:35:00 2026 GMT
notAfter=May  8 17:35:00 2041 GMT
X509v3 Subject Alternative Name:
    DNS:*.whinynil.co, DNS:lewsnetter.whinynil.co, DNS:whinynil.co
```

Cert lifetime: 15 years (CF Origin CA default). Issuer is the Cloudflare
Origin SSL Certificate Authority — exactly what CF's Full (Strict) mode
will validate against.

A `curl` to the origin's TLS port directly with SNI also succeeds:

```
$ curl -skI -o /dev/null -w "%{http_code}\n" \
    --resolve lewsnetter.whinynil.co:443:178.156.185.100 \
    https://lewsnetter.whinynil.co/up
200
```

(`-k` is required because the Origin CA root isn't in the system trust
store — it's only trusted by Cloudflare's edge, which is the point.)

## Verification: Cloudflare still returns 200 (Flexible mode, edge → origin still HTTP)

```
$ curl -sI -o /dev/null -w "via_cf_status=%{http_code}\n" https://lewsnetter.whinynil.co/up
via_cf_status=200

$ curl -sI https://lewsnetter.whinynil.co/up | head -5
HTTP/2 200
date: Wed, 13 May 2026 00:51:31 GMT
content-type: text/html; charset=utf-8
cache-control: max-age=0, private, must-revalidate
...
server: cloudflare
cf-ray: 9fadacda7b8da700-ORD
```

Both the HTTP and HTTPS ports on the origin respond with 200:

```
$ curl -sI -o /dev/null -w "%{http_code}\n" \
    -H "Host: lewsnetter.whinynil.co" http://178.156.185.100/up
200
```

That means CF can switch its CF→origin leg from HTTP (Flexible) to HTTPS
(Full Strict) without the app missing a beat — both ports serve.

## SAN coverage note

The current Origin CA cert SANs are:

- `*.whinynil.co`
- `lewsnetter.whinynil.co`
- `whinynil.co`

It does **not** cover `email.influencekit.com` (different zone). Kamal-proxy
will present this cert for all hosts it serves, including
`email.influencekit.com`. Implications:

- The `whinynil.co` zone is safe to flip to **Full (Strict)** — the
  cert is valid for the host being requested.
- The `influencekit.com` zone must stay on **Flexible** (or **Full**,
  not Full Strict) until either (a) a new Origin CA cert is minted
  covering both apex/wildcard pairs, or (b) we mint a separate cert for
  `email.influencekit.com` and find a way to teach kamal-proxy to do
  SNI-based cert selection (not currently supported as of kamal-proxy
  v0.9.2 / Kamal 2.11 — `proxy.ssl` is a single cert/key pair per app).

For MVP the priority is the platform host; the tenant unsub subdomain is
documented as a follow-up. See "Open follow-ups" below.

## Exact Cloudflare flip procedure (for Bruno)

You'll do this in the **whinynil.co** zone only.

1. Open: <https://dash.cloudflare.com/?to=/:account/whinynil.co/ssl-tls>
2. Pick **SSL/TLS** → **Overview** in the left sidebar.
3. Set **SSL/TLS encryption mode** to **Full (Strict)**.
4. Wait ~10 seconds for it to apply, then verify:

   ```
   curl -sI https://lewsnetter.whinynil.co/up | head -3
   ```

   Expect `HTTP/2 200`. Visit `https://lewsnetter.whinynil.co` in a
   browser and confirm the sign-in page renders + the padlock is green.
5. In **SSL/TLS** → **Edge Certificates**, the **Always Use HTTPS** and
   **Minimum TLS Version** settings can stay where they are; **Full
   (Strict)** is the only mode change needed.

Do **not** flip the `influencekit.com` zone — leave it on Flexible.
That zone's SSL mode is independent of `whinynil.co`'s.

## Rollback if Full (Strict) breaks anything

If the site goes red / 5xx after the flip:

1. Same dashboard: SSL/TLS → Overview → set mode back to **Flexible**.
   CF→origin reverts to HTTP and the existing healthy path resumes.
2. From your laptop confirm: `curl -sI https://lewsnetter.whinynil.co/up`
   returns 200 again.
3. Inspect what went wrong. Most likely causes:
   - Cert expired (won't happen for 15 years).
   - Cert/key got out of sync on the host (re-deploy:
     `mise x -- bundle exec kamal deploy`).
   - Kamal-proxy restarted without the bind-mounted cert dir (run
     `mise x -- bundle exec kamal proxy reboot` to recreate the
     container with the same mounts, then re-deploy).
4. The cert + key on the host live at
   `/root/.kamal/proxy/apps-config/lewsnetter/tls/web/{cert,key}.pem`
   and inside the container at
   `/home/kamal-proxy/.apps-config/lewsnetter/tls/web/{cert,key}.pem`.
   `docker exec kamal-proxy ls /home/kamal-proxy/.apps-config/lewsnetter/tls/web/`
   confirms they're mounted.

## Rotating the Origin CA cert

When the cert eventually needs rotation (or to add a new SAN):

1. Mint a new Origin CA cert in the CF dashboard
   (SSL/TLS → Origin Server → Create Certificate).
2. Update `ORIGIN_CERT` and `ORIGIN_KEY` in
   `~/Projects/rails/lewsnetter/.kamal/secrets` (single quotes, multi-line PEM).
3. `mise x -- bundle exec kamal deploy`. Kamal re-uploads + bind-mounts
   automatically, and `kamal-proxy deploy` reloads the cert without
   restarting the container.

## Open follow-ups

- **email.influencekit.com SAN coverage.** Either mint a new Origin CA
  cert that covers both `lewsnetter.whinynil.co` and
  `email.influencekit.com`, or stand up a per-host cert mechanism.
  Until then, the `influencekit.com` zone has to stay on Flexible. If
  kamal-proxy ever ships SNI-based multi-cert support, revisit this.
- **HSTS at the origin.** Once Full (Strict) is locked in we can add
  `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`
  at the app layer (Rails `force_ssl` already adds HSTS — make sure the
  Rails env has `config.force_ssl = true` in production). The CF response
  above already includes HSTS from the edge.
- **Remove `ssl_redirect: false`.** Once Full (Strict) is stable and
  CF→origin is always HTTPS, we can let kamal-proxy enforce the redirect
  as a belt-and-suspenders defense. Optional polish, not blocking.
