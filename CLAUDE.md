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
| `/wiki` | Clean notes **and design docs**. One topic per file, kebab-case. Design docs are named `<KEY>-<slug>.md`. |
| `/archive` | Processed `/raw` files land here. Permanent, immutable record. |
| `/coding` | Engineering notes **and** reusable orchestration prompts/workflows for multi-step coding tasks. |
| `/prompts` | Standing prompts run against the vault (e.g. `translate.md`). |
| `/tickets` | One file per Jira ticket. See the ticket protocol below. |
| `/skills` | Versioned source of truth for personal Claude Code skills. Installed to `~/.claude/skills` by `skills/install.ps1`. |
| `/user-memory` | Template for `~/.claude/CLAUDE.md`, the user-level memory that imports this vault into every repo. Installed by `user-memory/install.ps1`. |

---

## Common Tasks

- **Log ticket work** → create or append to `/tickets/<KEY>.md` following the ticket protocol.
- **Coding orchestration** → check `/coding` for an existing prompt or workflow before inventing a new one. If a multi-step coding task recurs, write it down in `/coding` as a reusable prompt.
- **Think through a ticket or idea** → Phase 1. Run `/grill-me`, `/grill-with-docs`, or `/grilling`, then file the agreed output as a design doc in `/wiki`. See the design doc protocol below.
- **Implement a ticket** → Phase 2. Run it through the four-agent pipeline in `coding/four-agent-pipeline.md`, with the design doc as the input. This is the default path for ticket work, not an option.
- **Answer questions** → read `/wiki`, `/tickets`, and `/archive` to answer ad-hoc questions about past thinking and past work.
- **Install skills** → run `skills/install.ps1` after any `git pull` that touches `/skills`. Same vault-is-source pattern as `coding/ship/install.ps1`.
- **Install user memory** → run `user-memory/install.ps1` to point `~/.claude/CLAUDE.md` at this vault. Resolves the vault path per machine, so it works from any checkout location.

**Skills — where they come from.** `/skills` holds all 48. 23 of them originate from the `npx agents` installer, which writes to `~/.agents/skills`; a `SessionStart` hook (`~/.claude/sync-skills.sh`) copies that folder into `~/.claude/skills` on every session start. That hook runs **after** this vault's installer and will overwrite those 23 with the upstream copy. So for those, the vault copy is a versioned backup, not the live authority. The other 25 (the `aws-*` set, `cloudwatch`, `investigate-ticket`, `playwriter`, `signing-in-to-aws`) have no upstream — the vault is their only copy. To make the vault authoritative for all 48, retire the `sync-skills.sh` hook and update the 23 by re-syncing `~/.agents/skills` into `/skills` and committing.

---

## The Two-Phase Workflow

All coding work runs in two phases, in order. Never start Phase 2 without a Phase 1 document.

| Phase | What happens | Tool | Output |
| --- | --- | --- | --- |
| 1 — Decide | Relentless interview until Neru and the agent share an understanding | `/grill-me`, `/grill-with-docs`, `/grilling` | `/wiki/<KEY>-<slug>.md` |
| 2 — Build | Planner → Coder → Tester → Reviewer | `/ship` | code on a branch + `/tickets/<KEY>.md` entry |

- **Phase 1 is not optional for non-trivial work.** If asked to implement something with no design doc, say so and offer to grill it first.
- **Phase 2 reads Phase 1.** Hand the Planner the design doc, not a one-line restatement of the ask.
- **The document is the contract.** If the pipeline contradicts a decision in it, that is a stop and a revision — not a silent override.

---

## Design Doc Protocol

**Location:** `/wiki/<JIRA-KEY>-<slug>.md` — e.g. `wiki/PROJ-1234-rate-limiting.md`.

- Work that started as a raw idea with no ticket uses a bare kebab-case slug (`wiki/agent-memory-compaction.md`). Rename it through Obsidian once a key exists.
- One design doc per unit of work. It is **living** — amended after implementation, never superseded by a second file.

**Division of labour with `/tickets`:**

- The **wiki doc owns decisions** — every choice and the reasoning behind it, from both phases.
- The **ticket owns the log** — dated activity, what was touched, pipeline verdict, blockers.
- They link to each other. Never duplicate decisions into the ticket; link to the wiki doc instead.

**Writing it:**

- Same voice as the rest of `/wiki`: bulleted, scannable, terse. No executive summary, no filler.
- **Preserve Neru's own words** for the decisions. The grilling output is a record of what *he* decided — do not sand his reasoning into neutral tone.
- **Rejected options are content, not clutter.** The reason an option was discarded is the most valuable thing in the file six months later.
- Record open questions as `OPEN QUESTION` — the same marker the Planner stops on.
- Never invent a decision that was not actually reached. An unresolved branch is an open question, not a default.

**After the pipeline runs**, append a dated revision to the same file — do not rewrite history above it:

- What the pipeline changed about the plan, and why.
- Any decision the Reviewer overturned or flagged.
- New open questions the implementation surfaced.

**Template:**

```markdown
# PROJ-1234 — <short title>

- **Status:** decided | in progress | implemented | superseded
- **Ticket:** [[tickets/PROJ-1234.md]]
- **Grilled:** YYYY-MM-DD via /grill-me
- **Last touched:** YYYY-MM-DD

## Problem

- What's actually broken or missing, in Neru's framing.

## Decisions

- **<decision>** — because <reasoning>.
- **<decision>** — because <reasoning>.

## Rejected

- **<option>** — rejected because <reasoning>.

## Scope

**In**
- ...

**Out**
- ...

## Open questions

- OPEN QUESTION: ...

---

## YYYY-MM-DD — post-implementation revision

**Changed**
- <decision> revised to <new> — because <what the build revealed>.

**Reviewer flagged**
- ...

**New open questions**
- ...
```

---

## Jira Ticket Protocol

**Location:** `/tickets/<JIRA-KEY>.md` — one file per ticket, named by key (e.g. `PROJ-1234.md`). A ticket accumulates dated entries over its life; never split one ticket across multiple files.

**Every ticket file carries:**

- Jira key, ticket title, current status
- A link to its design doc in `/wiki` (see the design doc protocol above)
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
- **The two project keys in play are `CBS` (Core Business Services) and `AS` (Apply Systems)** — both verified against Jira on 2026-09-15. `APPSYS` is Neru's spoken shorthand for Apply Systems and is **not** a Jira key; never write `APPSYS-*` in a filename or a link.
- Repos live under `C:\JT Repositories`. The team-to-repo inventory is in `README.md`. A repo that is not listed there has no assigned team — ask, do not assume.

**Dates:** always run `date` to get the real current date. Never assume or back-fill a date from memory.

**Implementation — the four-agent pipeline:**

- Phase 1 first: the ticket must have a design doc in `/wiki` before the pipeline runs. No doc, no pipeline.
- Every ticket that involves writing code runs through `coding/four-agent-pipeline.md`: Planner → Coder → Tester → Reviewer.
- Work on a branch named for the ticket (e.g. `feat/PROJ-1234-<slug>`). Never run the pipeline on `main`.
- The pipeline **never merges**. The reviewer's verdict is a recommendation; Neru is the final gate.
- Log the run in the ticket entry: verdict, what the reviewer flagged, and where the `.pipeline/` handoff files live.
- If a stage gate trips — spec has `OPEN QUESTION`, tests fail, verdict is `NEEDS WORK` or `BLOCK` — that goes in **Blockers / Open questions**, not silently retried.
- Skipping the pipeline **and Phase 1** is allowed for trivial work (one-line fix, config tweak, revert). Say so in the entry and why.

**Template:**

```markdown
# PROJ-1234 — <ticket title>

- **Status:** <status> (<source: jira | unverified>)
- **Design:** [[wiki/PROJ-1234-<slug>.md]]
- **Last touched:** YYYY-MM-DD

## YYYY-MM-DD

**Did**
- ...

**Decisions**
- ... — because ...

**Touched**
- repo/branch, PR #, files

**Pipeline**
- Verdict: SHIP | NEEDS WORK | BLOCK | not run (<why>)
- Stopped at: <stage, if it halted early>
- Reviewer flagged: ...

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

**Stacks in play:** .NET (C#) and Node/TypeScript. Anything outside these two is unconfirmed — ask before assuming a language, framework, test runner, or lint setup.

### Stack defaults

These are conventional starting points, **not verified against any specific repo**. Treat them as a first guess to confirm, never as a command to run blind.

| Stack | Test | Build | Notes |
| --- | --- | --- | --- |
| .NET (C#) | `dotnet test` | `dotnet build` | Solution-scoped by default; a repo may need `--filter` or a named `.sln`. |
| Node/TypeScript | `npm test` | `npm run build` | Confirm the package manager first — pnpm and yarn are not interchangeable with npm here. |

### Per-repo pinned commands

**Pin the test command per repo before the first pipeline run there.** The Tester stage executes a real suite; without a known runner it guesses, and a guessed green is worse than no test at all. Add a row the first time the pipeline touches a repo — a repo with no row here has not been verified.

Repos, their stacks, and their real test-readiness are in `README.md`. **11 of the 24 repos have no tests at all** and several declare commands pointing at missing files — see the Test readiness section there before any pipeline run. This table records only commands **verified by actually running them**.

| Repo | Test command | Build command | Confirmed |
| --- | --- | --- | --- |
| _(none pinned yet)_ | | | |

### General

- When a coding convention gets decided, write it here rather than rediscovering it each session.
- **`.pipeline/` is gitignored** in every repo that uses the pipeline. It is scratch handoff state, not source.
