# Jira Ticket Protocol

> **Single source of truth.** Scope: **travels** — ticket files live in the vault even when the code work happens in a repo elsewhere.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

**Location:** `/tickets/<TEAM>/<JIRA-KEY>.md` — one file per ticket, named by key (e.g. `tickets/CBS/CBS-1234.md`). `<TEAM>` is `CBS` or `AS`. A ticket accumulates dated entries over its life; never split one ticket across multiple files.

**Template:** [`templates/ticket.md`](../templates/ticket.md) — the only copy. Never inline a second copy of it anywhere.

**Frontmatter:** see [the frontmatter contract](frontmatter.md).

## Every ticket file carries

- Jira key, ticket title, current status
- A link to its design doc, **by bare name** (`[[CBS-1234-rate-limiting]]`) — see [the design doc protocol](design-docs.md). The doc moves folders over its life; the ticket does not.
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
- **Neru's own two project keys are `CBS` (Core Business Services) and `AS` (Apply Systems)** — both verified against Jira on 2026-09-15. `APPSYS` is Neru's spoken shorthand for Apply Systems and is **not** a Jira key; never write `APPSYS-*` in a filename or a link.
- **`PST` (Partnerships Team) is a real third key** — verified against Jira on 2026-09-17. It owns `atsapi-v6` / ats-api. Work on a repo Neru does not own still gets filed under the owning team's key; filing it under `CBS` or `AS` would invent a team assignment.
- ⚠️ **The GitLab-group heuristic is not reliable for ownership.** `atsapi-v6`'s local remote is `oneclick/atsapi-v6`, while PST-6617/6618 describe it as `platform/core-api/ats-api` — the *CBS* group pattern in [`README.md`](../README.md). **Jira keys in the repo's commit messages are the stronger signal**; check those before trusting the group path.
- Repos live under `C:\JT Repositories`. The team-to-repo inventory is the repo tables in [`README.md`](../README.md) — the only copy. A repo that is not listed there has no assigned team; ask, do not assume.

## What to log about a pipeline run

How the pipeline behaves is [the workflow protocol](workflow.md) and [`coding/four-agent-pipeline.md`](../coding/four-agent-pipeline.md). This section is only about what lands in the ticket file.

- Log the run in the ticket entry: verdict, what the reviewer flagged, and where the `.pipeline/` handoff files live.
- **If a stage gate trips, that goes in Blockers / Open questions** — not silently retried.
- Skipping the pipeline **and Phase 1** is allowed for trivial work (one-line fix, config tweak, revert). Say so in the entry and why.
