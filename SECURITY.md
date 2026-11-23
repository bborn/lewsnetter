# Security Policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability** (https://github.com/bborn/lewsnetter/security/advisories/new). Don't open a public issue or pull request for a suspected vulnerability.

Include what you can of:

- the affected area (campaign sending, segments, subscribers, the REST API, the MCP server, the in-app agent, OAuth, SES or Stripe webhooks, the admin panel) and the commit you tested
- steps to reproduce, ideally as a failing test against `master`
- the impact you expect an attacker could achieve
- a suggested patch, if you have one

You'll get a reply within a few days. We fix it on `master`, deploy, and agree on timing with you before anything is made public. The published advisory credits you unless you'd rather stay anonymous. Please don't test against https://app.lewsnetter.dev or any other live instance you don't run yourself; a local install with synthetic data is enough.

## Supported versions

Fixes land on `master` and deploy from there. Only the latest `master` is supported. Fixes aren't backported, so if you self-host, update to the latest `master`.

## Scope

Lewsnetter is multi-tenant. These are in scope and matter most:

- reading or changing another team's data (subscribers, campaigns, segments, events, templates, sender addresses)
- sending email to people who shouldn't receive it, or from a sender a team hasn't verified
- bypassing OAuth token scopes, a token's team binding, or the in-app agent's approval prompts
- injection into rendered email or the app UI
- leaking credentials (SES keys, LLM keys, tokens)

Out of scope: findings that need an admin or developer account (`DEVELOPER_EMAILS`) on an instance you control, denial of service through sheer volume, missing best-practice headers with no demonstrated impact, and reports from automated scanners without a working reproduction.
