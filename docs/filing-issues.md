# Filing issues

A good issue lets a stranger reproduce the problem in ten minutes without asking you anything. That's the bar for humans and agents alike. The issue forms in `.github/ISSUE_TEMPLATE/` follow this guide.

Security problems don't go in issues. See [SECURITY.md](../SECURITY.md).

## Before you file

1. Reproduce it yourself on current `master`, or on app.lewsnetter.dev if that's where you saw it. If you can't, say so and give what you have; don't present a guess as a repro.
2. Search open and closed issues. If one exists, comment there instead.
3. Keep what you **observed** separate from what you **think the cause is**. Both are welcome; label them.

## What a bug report contains

1. **Summary.** Two or three sentences: what you did, what happened, what you expected.
2. **Version and environment.** The commit, how you run it (bin/dev, Docker, Kamal), SES region and LLM provider if they're involved.
3. **Steps to reproduce.** Numbered, copy-pasteable, minimal. A failing test at the code path is the best repro of all. Note anything you tried that did **not** reproduce it.
4. **Expected vs actual.** Paste actual output verbatim: log lines, HTTP responses, MCP tool results. For visual bugs attach a screenshot and say what to look at.
5. **Evidence.** Trimmed logs, and code permalinks with a commit SHA (`https://github.com/bborn/lewsnetter/blob/<sha>/<path>#L<n>-L<m>`). Branch links rot.
6. **What you ruled out.** One line each: "not a duplicate of #N because …", "still happens on master at `<sha>`".

## Feature requests and tasks

Feature requests describe the workflow you couldn't complete and why the current behaviour falls short. Per [CONTRIBUTING.md](../CONTRIBUTING.md), get sign-off on the issue before opening a pull request for a feature or UI change.

Tasks (refactors, docs, chores) state the concrete work and its acceptance criteria.

## Rules for agents

- Reproduce before you file. If a live repro is impossible, write a failing test at the exact code path and mark the issue unverified.
- Question the report you were handed. If the stated cause is wrong, say what you observed and what you refuted.
- Include the base commit you tested against and permalinks to the code you cite.
- Don't open duplicates. If you find the same root cause under a different symptom, add your evidence to the existing issue.
- End the body with `> AGENT GENERATED`.

## Triage

A triage bot gives every new issue a first pass. Its comments start with a `SLOP COP` header. It adds a type and area labels and tries to reproduce bugs. A maintainer makes the final call.
