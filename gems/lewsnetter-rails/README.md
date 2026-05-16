# lewsnetter-rails

Push user data + custom attributes from a Rails app into [Lewsnetter](https://github.com/bborn/lewsnetter). Mirrors the `intercom-rails` pattern.

## Why

Your Rails app is the source of truth for users. Lewsnetter is the mirror you segment + send campaigns from. This gem keeps the mirror current with one `after_commit` hook per write and a nightly catch-up for misses.

## Install

```ruby
# Gemfile (in your source app — e.g. InfluenceKit)
gem "lewsnetter-rails", path: "/path/to/lewsnetter/gems/lewsnetter-rails"
```

## Configure

```ruby
# config/initializers/lewsnetter.rb
LewsnetterRails.configure do |c|
  c.base_url  = ENV["LEWSNETTER_URL"]        # https://lewsnetter.yourdomain.co
  c.api_token = ENV["LEWSNETTER_API_TOKEN"]  # Bearer token for /api/v1
  c.team_slug = ENV["LEWSNETTER_TEAM_SLUG"]  # which team to sync into
  c.enabled   = !Rails.env.test?
  c.logger    = Rails.logger
end
```

## Sync on write

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include LewsnetterRails::ActsAsSubscriber
  acts_as_lewsnetter_subscriber mapper: "Lewsnetter::UserMapper",
    only_if: -> { confirmed_at.present? }   # optional
end

# app/models/lewsnetter/user_mapper.rb
class Lewsnetter::UserMapper
  def self.call(user)
    {
      external_id: user.id.to_s,
      email:       user.email,
      name:        user.full_name,
      subscribed:  !user.email_opt_out?,
      attributes: {
        tenant_type:  user.tenant_type,        # "brand" | "events" | "influencer"
        tabs_enabled: user.tabs_enabled,       # array OR CSV string — Lewsnetter normalizes
        plan:         user.plan,
        subdomain:    user.subdomain,
        last_seen_at: user.last_sign_in_at
      }
    }
  end
end
```

Every save → fires `LewsnetterRails::SyncJob` → POSTs to `/api/v1/teams/:slug/subscribers/bulk`. Idempotent on `external_id`, so retries are safe.

## Nightly catch-up

Webhook-style sync can miss a deploy, a job-system blip, or any record updated before the gem was installed. Backfill closes the gap:

```ruby
# A scheduled job (cron, GoodJob, SolidQueue cron, etc.)
class LewsnetterBackfillJob < ApplicationJob
  def perform
    LewsnetterRails::Backfill.run(
      User.where("updated_at > ?", 25.hours.ago),
      mapper: "Lewsnetter::UserMapper"
    )
  end
end
```

For a first-run full backfill: pass `User.all` (or whatever scope you want).

## Tests

```ruby
# Disable in tests by default
RSpec.configure do |c|
  c.before { LewsnetterRails.configuration.enabled = false }
end
```

## What's on the Lewsnetter side

This gem talks to three endpoints, all of which already exist:

| Endpoint                                                                   | Used by               |
|----------------------------------------------------------------------------|-----------------------|
| `POST /api/v1/teams/:slug/subscribers/bulk` (NDJSON)                       | SyncJob, Backfill     |
| `DELETE /api/v1/teams/:slug/subscribers/by_external_id/:external_id`       | destroy hook          |

The bulk endpoint auto-normalizes list-like custom attributes — so if you ship `tabs_enabled: "billing,brand_account,reports"` it lands as `["billing","brand_account","reports"]` and segments correctly with element-wise matching. (You can also ship arrays directly — the normalizer is idempotent.)
