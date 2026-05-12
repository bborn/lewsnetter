# Lewsnetter

AI-native, owned-audience email marketing on Rails. Multitenant SaaS, open source from day 1.

Brief in → segment, draft, personalize, send, analyze → human approves at each gate. The product is a marketing co-pilot, not a sender.

See [`initiatives/lewsnetter-v2/PLAN.md`](initiatives/lewsnetter-v2/PLAN.md) for the full plan, data model, and roadmap.

## Status

Pre-MVP. Bruno is tenant zero (InfluenceKit brand newsletter is the forcing function). Not publicly sellable yet — first goal is sending IK's brand newsletter through Lewsnetter, replacing Intercom.

The 2014 codebase that previously lived here is archived on the [`legacy-2014`](https://github.com/bborn/lewsnetter/tree/legacy-2014) branch.

## Stack

- Rails 8.1 on Ruby 4
- [BulletTrain](https://bullettrain.co) (MIT) — Teams as tenant boundary, Devise + invitations, CanCanCan, Pay/Stripe billing
- PostgreSQL, Redis, Solid Queue, Solid Cache
- `aws-sdk-sesv2` + `mailkick` for sending, bounces, complaints, suppression sync
- `mjml-rails` for responsive email templates
- `ruby_llm` + `ruby_llm-agent` for the AI spine
- Hotwire (Turbo + Stimulus), Tailwind

## Getting started

Prerequisites:

- Ruby (see [`.ruby-version`](.ruby-version))
- Node (see [`.nvmrc`](.nvmrc))
- PostgreSQL 14+
- Redis 6.2+
- Chrome (system tests)

```sh
bin/setup
bin/dev
```

Then visit http://localhost:3000.

## License

MIT — see [`MIT-LICENSE`](MIT-LICENSE). Inherits BulletTrain's MIT license.
