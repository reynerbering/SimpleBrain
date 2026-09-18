# Vault Map

> **Single source of truth.** Scope: **vault-only** — do NOT apply these rules in a code repo.
> Linked (not imported) from `CLAUDE.md`, so read it when working in the vault. Do not restate it in `README.md`.

| Folder | Purpose |
| --- | --- |
| `/raw` | Inbox. Anything captured: notes, PDFs, screenshots, links. Unprocessed. |
| `/in-progress` | Every unfinished design doc, foldered `CBS/` and `AS/`. Parked work stays here too, flagged `later:`. |
| `/wiki` | Clean notes and **done** design docs, filed `<WEEK>/<TEAM>/` — one folder per working week, named by its Monday. Plus `/wiki/repos/`, outside the lifecycle. One topic per file, kebab-case. |
| `/archive` | Processed `/raw` files land here. Permanent, immutable record. |
| `/coding` | Engineering notes and reusable orchestration prompts. Holds `coding/ship/` — the live `/ship` agents, command, and installer — plus `coding/ship-workflow.js`, the Workflow-script variant of the same pipeline. |
| `/prompts` | Standing prompts run against the vault. Currently empty. |
| `/protocols` | The rules themselves. One file per topic, each the single source of truth for it. |
| `/templates` | Obsidian templates for a design doc and a ticket. Set as the Templates plugin folder. |
| `/tickets` | One file per Jira ticket, foldered `CBS/` and `AS/`. Never moves. |
| `/skills` | Versioned source of truth for personal Claude Code skills. |
| `/user-memory` | Template for `~/.claude/CLAUDE.md`, the user-level memory that imports this vault into every repo. |

## Root files

| File | Holds |
| --- | --- |
| `CLAUDE.md` | Who Neru is, common tasks, hard rules, and the imports/links into `/protocols`. Holds no protocol text of its own. |
| `README.md` | What the vault is, an index into `/protocols`, and the **repo inventory** — the one thing that lives nowhere else. |
| `AGENTS.md` | A pointer to the other two, for agents that look for that filename. Never put rules in it. |

## Flow through the folders

- Capture lands in `/raw`, unprocessed.
- Processing turns it into a clean entry in `/wiki`; the original moves to `/archive` so it is visible what has been handled.
- A design doc sits in `/in-progress` for its whole working life and moves into `/wiki/<WEEK>/<TEAM>/` once, when Neru marks it done. Parking flags it in place rather than moving it. That lifecycle is [the workflow protocol](workflow.md#where-work-lives) — the only copy.
- `/archive` is append-only. Nothing is ever edited or removed once it lands.

The rules enforcing this are the Hard Rules in [`CLAUDE.md`](../CLAUDE.md) — the only copy.
