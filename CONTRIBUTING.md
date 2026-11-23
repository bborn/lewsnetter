# Contributing

Thanks for helping improve Lewsnetter. Humans and AI agents are both welcome here, and both are held to the same bar.

## Before you open a pull request

A pull request from outside the maintainers must meet all of these:

1. **Approved author.** Your GitHub handle is on [`.github/APPROVED_CONTRIBUTORS`](.github/APPROVED_CONTRIBUTORS). See [Contributor approval](#contributor-approval).
2. **Linked issue.** The description closes an open issue in this repo, for example `Fixes #123`. See [Linked issue](#linked-issue).
3. **Maintainer edits.** You opened it from your fork with "Allow edits by maintainers" turned on. We often push small fixes to your branch before merging, and this setting lets us do that.

The PR gate closes a pull request that misses any of these and leaves a comment saying what's missing. A closed pull request is not a review of the change.

## Contributor approval

Anyone can open an issue, and issues need no approval.

1. Open an issue for the change, or find an existing one. Features and UI changes need sign-off first (see below).
2. Open the pull request with `Fixes #<number>` in its description. The gate closes it because you aren't approved yet. That's expected.
3. Comment on the issue with a link to the closed pull request and a short note on what it changes and why.

A maintainer then approves you by commenting `/approve @your-handle`, which adds you to the list, and reopens the pull request. Once you're on the list, you stay on it.

## Linked issue

Every pull request from outside the maintainers must close an open issue in this repo. The issue records the problem itself, so it stays tracked even if a pull request is reworked, closed, or replaced by a different fix.

Write `Fixes #<number>`, `Closes #<number>` or `Resolves #<number>` in the description. A plain mention doesn't count. If the gate closed your pull request only for a missing link, add the line and save the description. The pull request reopens on its own.

A maintainer can exempt a pull request by adding the `skip-issue-check` label.

## What a good pull request looks like

- **One issue, one change.** Keep unrelated cleanups out. If you find a second bug, open a second issue.
- **Root cause, not symptom.** Say in the description what was actually wrong.
- **A test that fails on master and passes with your change**, at the code path that broke. Behaviour changes without a test get sent back.
- **Checks pass locally:** the test files you touched, `bin/rails test` if you can, and `bundle exec standardrb`.
- **Follow [AGENTS.md](AGENTS.md)** for conventions: every MCP tool scopes to `context.team`, use `find_by!(id:)` instead of `.find`, no hardcoded hostnames or brand strings, and read [DESIGN.md](DESIGN.md) before any visual change.
- Fill in the pull request template.

Expect us to push small fixes to your branch (a missing test, a lint fix, an edge case) rather than ask you for another round. We'll say what we changed when we merge.

## Bugs

Open an issue with the bug report form and follow [docs/filing-issues.md](docs/filing-issues.md): what you did, minimal steps, expected vs actual, and what you ruled out. A stranger should be able to reproduce it from the issue alone. If you fix it, open a pull request that links the issue.

## Features and UI changes

Open an issue and wait for a maintainer's sign-off before opening a pull request. Lewsnetter is deliberately small, and some reasonable features are out of scope on purpose (for example, there's no visual flow builder; the agent and scheduled jobs cover that). Prototype links from your fork are welcome on the issue.

## Security problems

Don't open a public issue or pull request for a vulnerability. Report it privately: see [SECURITY.md](SECURITY.md).

## Contributions from AI agents

Agents open many of our issues and pull requests, and that's fine. The bar above applies, plus:

- **Reproduce before you file or fix.** A log line or a hunch is not a bug report. If you can't reproduce it live, write the closest faithful repro (a failing test at the exact code path) and say the report is unverified.
- **Question what you were told.** If the stated cause turns out to be wrong, say what you actually observed.
- **Cite the base commit** you tested against, and link code with commit permalinks (`blob/<sha>/path#L10-L20`), not branch links.
- **Search for duplicates first.** If you find the same root cause under a different symptom, add your evidence to the existing issue.
- **Leave the "Human comments" section of the pull request template empty.** It's for the person who sent you.
- **End the issue or pull request body with `> AGENT GENERATED`.**

## Triage

New issues and pull requests get an automated first pass from a triage bot. Its comments start with a `SLOP COP` header. It classifies and labels issues, tries to reproduce bugs, and may open a small fix pull request. A maintainer still makes every merge and product decision.
