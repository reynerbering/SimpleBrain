# Jira Ticket Protocol

> **Single source of truth.** Scope: **travels** — ticket files live in the vault even when the code work happens in a repo elsewhere.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

**Location:** `/tickets/<JIRA-KEY>.md` — one file per ticket, named by key (e.g. `CBS-1234.md`). A ticket accumulates dated entries over its life; never split one ticket across multiple files.

**Template:** [`templates/ticket.md`](../templates/ticket.md) — the only copy. Never inline a second copy of it anywhere.

**Frontmatter:** see [the frontmatter contract](frontmatter.md).

## Every ticket file carries

- Jira key, ticket title, current status
- A link to its design doc in `/wiki` — see [the design doc protocol](design-docs.md)
- A dated log — one dated section per working session, newest at the bottom

## Every dated entry captures

- **Did** — what was actually done
- **Decisions** — technical decisions made, with the reasoning behind them
- **Touched** — repos, branches, PRs, and key files changed
- **Blockers / Open questions** — what's stuck, who's needed, what's unresolved

## Sourcing ticket data

- Pull title, status, and description from Jira via the Atlassian MCP connector when it is available.
- If the connector is not authorized or reachable, build the entry from `/raw` and **explicitly mark** the unverified fields (e.g. `status: In Progress (unverified — Jira not reachable)`). Do not guess a status or title.
- Never invent a Jira key. If the key is unknown, log it as `UNKNOWN-KEY` and flag it in the entry.
- **The two project keys in play are `CBS` (Core Business Services) and `AS` (Apply Systems)** — both verified against Jira on 2026-09-15. `APPSYS` is Neru's spoken shorthand for Apply Systems and is **not** a Jira key; never write `APPSYS-*` in a filename or a link.
- Repos live under `C:\JT Repositories`. The team-to-repo inventory is the repo tables in [`README.md`](../README.md) — the only copy. A repo that is not listed there has no assigned team; ask, do not assume.

## What to log about a pipeline run

How the pipeline behaves is [the workflow protocol](workflow.md) and [`coding/four-agent-pipeline.md`](../coding/four-agent-pipeline.md). This section is only about what lands in the ticket file.

- Log the run in the ticket entry: verdict, what the reviewer flagged, and where the `.pipeline/` handoff files live.
- **If a stage gate trips, that goes in Blockers / Open questions** — not silently retried.
- Skipping the pipeline **and Phase 1** is allowed for trivial work (one-line fix, config tweak, revert). Say so in the entry and why.
