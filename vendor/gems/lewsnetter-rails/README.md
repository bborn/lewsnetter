# lewsnetter-rails

Rails client for [Lewsnetter](https://lewsnetter.com). Pushes subscribers and
behavioral events from your application to your Lewsnetter team via the
`/api/v1/teams/:team_id/...` HTTP API.

Zero runtime dependencies beyond `activejob` — uses Ruby's stdlib `Net::HTTP`.

## Install

```ruby
# Gemfile
gem "lewsnetter-rails"
```

```ruby
# config/initializers/lewsnetter.rb
Lewsnetter.configure do |c|
  c.api_key  = Rails.application.credentials.lewsnetter_api_key
  c.team_id  = Rails.application.credentials.lewsnetter_team_id
  c.endpoint = "https://app.lewsnetter.com/api/v1"
  # c.async = false       # run inline instead of via ActiveJob
  # c.logger = Rails.logger
end
```

The `api_key` is a Platform::AccessToken plaintext token, provisioned for the
host app via Lewsnetter's BulletTrain Doorkeeper integration.

## Sync a model

```ruby
class User < ApplicationRecord
  acts_as_lewsnetter_subscriber(
    external_id: :id,
    email: :email,
    name: :full_name,
    attributes: ->(u) {
      {
        plan: u.tenant.plan_tier,
        mrr_cents: u.tenant.mrr_cents,
        signed_up_at: u.created_at,
        is_paying: u.tenant.paying?
      }
    }
  )
end
```

After `create`/`update` commits the record is enqueued for upsert via
`Lewsnetter::SyncJob`. On `destroy`, the subscriber is deleted from Lewsnetter.

## Track events

```ruby
Lewsnetter.track(user, "report_viewed", report_id: report.id)
```

## Backfill

```ruby
Lewsnetter.bulk_upsert(User.where(active: true))
# => {"processed" => 1234, "created" => 200, "updated" => 1034, "errors" => []}
```

## Errors

- `Lewsnetter::AuthenticationError` — 401/403. `SyncJob` discards rather than retrying.
- `Lewsnetter::RateLimitedError` — 429. Retried via ActiveJob with backoff; respects `Retry-After`.
- `Lewsnetter::ApiError` — other 4xx/5xx and network errors. Retried.

## Wire format

- Subscriber upsert: `POST /teams/:team_id/subscribers` with `{"subscriber": {...}}`.
- Bulk: `POST /teams/:team_id/subscribers/bulk` with `Content-Type: application/x-ndjson`.
- Event: `POST /teams/:team_id/events/track` with `{external_id, event, occurred_at, properties}`.
- Delete: `DELETE /teams/:team_id/subscribers/by_external_id/:external_id`.

Every mutating request includes an `Idempotency-Key` header (sha256 of the
external_id + payload).
