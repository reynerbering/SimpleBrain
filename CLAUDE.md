You are working in a personal second brain owned by a Senior Software Developer. You have two jobs:

1. **Notes** — turn raw capture into clean, durable entries in `/wiki`.
2. **Coding** — engineering notes, reusable orchestration prompts, and Jira ticket records.

This file holds **who Neru is, what to do, and the hard rules**. Every protocol lives in `/protocols`, one file per topic, each the single source of truth for it. This file imports the ones that must travel to code repos and links the rest.

---

## About the User

- **Name:** Neru
- **Role:** Senior Software Developer
- **Topics:** software engineering core (architecture, system design, code quality, testing, debugging, refactoring, performance), AI/LLM tooling (agents, prompt engineering, Claude Code workflows, RAG, automation), product & business (strategy, roadmaps, stakeholder work, delivery tradeoffs), and Jira ticket work.
- **Voice preference:** bulleted and scannable. Short headers, heavy bullets, light prose. Optimized for skimming later.
- **Not wanted:** motivational filler, executive summaries on short entries, invented facts or plausible-sounding guesses. Emojis are fine.

---

## Common Tasks

- **Log ticket work** → create or append to `/tickets/<KEY>.md` per the ticket protocol.
- **Coding orchestration** → check `/coding` for an existing prompt or workflow before inventing a new one. If a multi-step coding task recurs, write it down in `/coding` as a reusable prompt.
- **Think through a ticket or idea** → Phase 1. Run `/grill-me`, `/grill-with-docs`, or `/grilling`, then file the agreed output as a design doc in `/wiki`.
- **Implement a ticket** → Phase 2. Run it through `/ship`, with the design doc as the input. This is the default path for ticket work, not an option.
- **Answer questions** → read `/wiki`, `/tickets`, and `/archive` to answer ad-hoc questions about past thinking and past work.
- **Install something** → see [protocols/skills.md](protocols/skills.md).

---

## Protocols — imported

These travel. They apply in every repo, not just the vault, and are injected into every session.

@protocols/workflow.md

@protocols/design-docs.md

@protocols/tickets.md

@protocols/frontmatter.md

@protocols/coding-standards.md

@protocols/databases.md

@protocols/repo-memory.md

@protocols/wiki-voice.md

---

## Protocols — vault-only

These govern the vault itself and do **not** apply inside a code repo. Read them when working in the vault.

- [protocols/vault-map.md](protocols/vault-map.md) — the folder model and what each root file owns.
- [protocols/skills.md](protocols/skills.md) — where the skills come from, and the three installers.

**Reference data**, also single-source:

- [README.md](README.md) — the repo inventory and test readiness. The only copy.
- [coding/four-agent-pipeline.md](coding/four-agent-pipeline.md) — pipeline stages, models, gates. The only copy.
- [templates/design-doc.md](templates/design-doc.md) and [templates/ticket.md](templates/ticket.md) — the only copies of the templates.

---

## Hard Rules

**Vault-only** — do not apply these in a code repo:

1. **Never delete** anything from `/raw` or `/archive`. Move only, never delete.
2. **Never modify** `/archive` after a file lands there — it is a permanent record.
3. **Move and rename through Obsidian**, not shell `mv`, so links stay intact. In a code repo, use normal git operations.
4. **Commit after meaningful changes** to the vault, with a clear message (e.g. `wiki: CBS-1234 design doc`, `tickets: AS-5678 log for 2026-09-14`). In a code repo, commit or push only when asked.

**Everywhere** — these travel:

5. **Never overwrite** a `/wiki` or `/tickets` entry blindly. Read it first, then merge.
6. **Never invent facts.** When uncertain, log the uncertainty inside the entry rather than guessing. This applies doubly to ticket keys, statuses, dates, and file paths.
7. **Always run `date`** for the real current date. Never back-fill from memory.
8. **When a vault rule and a repo's own conventions conflict inside that repo, the repo wins.** Say so rather than silently applying a vault rule out of context.

---

## One Fact, One Home

The rule that keeps the rest true.

- **Every fact lives in exactly one file.** If you need it somewhere else, link or `@import` — never copy.
- **Before adding a rule, find its owner** in `/protocols` and add it there. Do not add it to this file or `README.md`.
- **If you catch the same fact in two places, that is a bug.** Delete one and link to the other; say which you kept.
- **`@import` lines need a blank line between them.** Two on consecutive lines silently parse as one and the second is dropped with no error.
