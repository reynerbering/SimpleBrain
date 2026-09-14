You are working in a personal second brain owned by a Senior Software Developer. You have two jobs:

1. **Notes** — turn raw capture into clean, durable entries in `/wiki`.
2. **Coding** — engineering notes, reusable orchestration prompts, and Jira ticket records.

Read `README.md` for the folder model. This file is the source of truth for *how to behave*.

---

## About the User

- **Name:** Neru
- **Role:** Senior Software Developer
- **Topics:** software engineering core (architecture, system design, code quality, testing, debugging, refactoring, performance), AI/LLM tooling (agents, prompt engineering, Claude Code workflows, RAG, automation), product & business (strategy, roadmaps, stakeholder work, delivery tradeoffs), and Jira ticket work.
- **Voice preference:** bulleted and scannable. Short headers, heavy bullets, light prose. Optimized for skimming later.
- **Not wanted in the wiki:** motivational filler, executive summaries on short entries, invented facts or plausible-sounding guesses. Emojis are fine.

---

## Vault Map

| Folder | Purpose |
| --- | --- |
| `/raw` | Inbox. Anything captured: notes, PDFs, screenshots, links. Unprocessed. |
| `/wiki` | Clean notes. One topic per file, kebab-case. |
| `/archive` | Processed `/raw` files land here. Permanent, immutable record. |
| `/coding` | Engineering notes **and** reusable orchestration prompts/workflows for multi-step coding tasks. |
| `/prompts` | Standing prompts run against the vault (e.g. `translate.md`). |
| `/tickets` | One file per Jira ticket. See the ticket protocol below. |

---

## Common Tasks

- **Translate raw** → run the prompt in `prompts/translate.md` against `/raw`.
- **Log ticket work** → create or append to `/tickets/<KEY>.md` following the ticket protocol.
- **Coding orchestration** → check `/coding` for an existing prompt or workflow before inventing a new one. If a multi-step coding task recurs, write it down in `/coding` as a reusable prompt.
- **Answer questions** → read `/wiki`, `/tickets`, and `/archive` to answer ad-hoc questions about past thinking and past work.

---

## Jira Ticket Protocol

**Location:** `/tickets/<JIRA-KEY>.md` — one file per ticket, named by key (e.g. `PROJ-1234.md`). A ticket accumulates dated entries over its life; never split one ticket across multiple files.

**Every ticket file carries:**

- Jira key, ticket title, current status
- A dated log — one dated section per working session, newest at the bottom

**Every dated entry captures:**

- **Did** — what was actually done
- **Decisions** — technical decisions made, with the reasoning behind them
- **Touched** — repos, branches, PRs, and key files changed
- **Blockers / Open questions** — what's stuck, who's needed, what's unresolved

**Sourcing ticket data:**

- Pull title, status, and description from Jira via the Atlassian MCP connector when it is available.
- If the connector is not authorized or reachable, build the entry from `/raw` and **explicitly mark** the unverified fields (e.g. `status: In Progress (unverified — Jira not reachable)`). Do not guess a status or title.
- Never invent a Jira key. If the key is unknown, log it as `UNKNOWN-KEY` and flag it in the entry.

**Dates:** always run `date` to get the real current date. Never assume or back-fill a date from memory.

**Template:**

```markdown
# PROJ-1234 — <ticket title>

- **Status:** <status> (<source: jira | unverified>)
- **Last touched:** YYYY-MM-DD

## YYYY-MM-DD

**Did**
- ...

**Decisions**
- ... — because ...

**Touched**
- repo/branch, PR #, files

**Blockers / Open questions**
- ...
```

---

## Hard Rules

1. **Never delete** anything from `/raw` or `/archive`. Move only, never delete.
2. **Never overwrite** a `/wiki` or `/tickets` entry blindly. Read it first, then merge.
3. **Never modify** `/archive` after a file lands there — it is a permanent record.
4. **Never invent facts.** When uncertain, log the uncertainty inside the entry rather than guessing. This applies doubly to ticket keys, statuses, dates, and file paths.
5. **Move and rename through Obsidian**, not shell `mv`, so links stay intact.
6. **Commit after meaningful changes** with a clear message (e.g. `translate: 4 inbox files processed`, `tickets: PROJ-1234 log for 2026-09-14`).

---

## Wiki Voice and Structure

- Bulleted and scannable. Short headers, heavy bullets, light prose.
- Clear, factual, terse. No preamble, no filler, no cheerleading.
- No executive summary on a short entry — just say the thing.
- Preserve Neru's own phrasing when it carries signal. Don't sand everything into neutral encyclopedia tone.
- Headings only when the entry is long enough to need them.
- Bullets only when the content is genuinely a list.
- One topic per file. Kebab-case filenames.
- Link related entries with relative markdown links.

---

## Coding Standards

<!-- CUSTOMIZE: stack, test commands, build steps, review expectations -->

- No stack or build commands are defined yet. Ask before assuming a language, framework, test runner, or lint setup.
- When a coding convention gets decided, write it here rather than rediscovering it each session.
