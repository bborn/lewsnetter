# lewsnetter-rails — sync subscribers from your Rails app

A Ruby gem that pushes user records + custom attributes from your existing Rails app into Lewsnetter on every save. Modeled on `intercom-rails` — if you've used that, this is the same idea.

**Full gem README:** [`gems/lewsnetter-rails/README.md`](../gems/lewsnetter-rails/README.md). This page is the short version.

## When to use it

| Source of truth | Use |
|---|---|
| Your Rails app's `User` table | `lewsnetter-rails` (live sync) |
| A spreadsheet, a CRM export | CSV import in the UI |
| A one-off list | Manual add through the UI |
| Anything programmatic, non-Rails | The REST API at `/api/v1/teams/:slug/subscribers/bulk` |

Use the gem when your Rails app is the canonical source of who exists and what attributes they have. It keeps Lewsnetter in sync so your segments stay accurate without manual exports.

## Install

In your other Rails app's Gemfile (NOT Lewsnetter itself):

```ruby
gem "lewsnetter-rails", git: "https://github.com/bborn/lewsnetter.git",
                       glob: "gems/lewsnetter-rails/*.gemspec"
```

## Configure

```ruby
# config/initializers/lewsnetter.rb
LewsnetterRails.configure do |c|
  c.base_url  = ENV["LEWSNETTER_URL"]        # e.g. https://app.lewsnetter.dev
  c.api_token = ENV["LEWSNETTER_API_TOKEN"]  # from Developers → Sync setup
  c.team_slug = ENV["LEWSNETTER_TEAM_SLUG"]  # which Lewsnetter team to sync into
  c.enabled   = !Rails.env.test?
end
```

Get the token + slug from **Developers → Sync setup** in Lewsnetter.

## Hook into your User model

```ruby
class User < ApplicationRecord
  include LewsnetterRails::ActsAsSubscriber
  acts_as_lewsnetter_subscriber mapper: "Lewsnetter::UserMapper",
    only_if: -> { confirmed_at.present? }
end
```

Define the mapper class — this is where you decide what attributes Lewsnetter sees:

```ruby
# app/models/lewsnetter/user_mapper.rb
class Lewsnetter::UserMapper
  def self.call(user)
    {
      external_id: user.id.to_s,
      email:       user.email,
      name:        user.full_name,
      subscribed:  !user.email_opt_out?,
      attributes: {
        plan:         user.plan,
        tenant_type:  user.tenant_type,
        last_seen_at: user.last_sign_in_at
      }
    }
  end
end
```

Every save → enqueues a background job → POSTs to Lewsnetter's bulk subscriber endpoint. Idempotent on `external_id`, so retries are safe.

## What about deletes?

The gem fires a delete sync on `destroy`. If you soft-delete instead, mark `subscribed: false` in your mapper.

## Catch-up

There's a rake task for syncing all users at once (e.g. after first install, or to catch any sync misses):

```sh
bundle exec rake lewsnetter:sync_all
```

Runs in batches, idempotent.

## Reference

See [`gems/lewsnetter-rails/README.md`](../gems/lewsnetter-rails/README.md) for: the full mapper DSL, error handling, custom job classes, telemetry, and the underlying HTTP contract if you want to call the API without the gem.
