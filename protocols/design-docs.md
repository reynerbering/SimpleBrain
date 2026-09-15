# Design Doc Protocol

> **Single source of truth.** Scope: **travels** — design docs are authored in the vault even when the code work happens in a repo elsewhere.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

**Location:** `/wiki/<JIRA-KEY>-<slug>.md` — e.g. `wiki/CBS-1234-rate-limiting.md`.

- Work that started as a raw idea with no ticket uses a bare kebab-case slug (`wiki/agent-memory-compaction.md`). Rename it through Obsidian once a key exists.
- One design doc per unit of work. It is **living** — amended after implementation, never superseded by a second file.

**Template:** [`templates/design-doc.md`](../templates/design-doc.md) — the only copy. Never inline a second copy of it anywhere.

**Frontmatter:** see [the frontmatter contract](frontmatter.md).

## Division of labour with `/tickets`

- The **wiki doc owns decisions** — every choice and the reasoning behind it, from both phases.
- The **ticket owns the log** — dated activity, what was touched, pipeline verdict, blockers.
- They link to each other. Never duplicate decisions into the ticket; link to the wiki doc instead.

## Writing it

- Same voice as the rest of `/wiki`: see [wiki voice](wiki-voice.md).
- **Preserve Neru's own words** for the decisions. The grilling output is a record of what *he* decided — do not sand his reasoning into neutral tone.
- **Rejected options are content, not clutter.** The reason an option was discarded is the most valuable thing in the file six months later.
- Record open questions as `OPEN QUESTION` — the same marker the Planner stops on.
- Never invent a decision that was not actually reached. An unresolved branch is an open question, not a default.

## After the pipeline runs

Append a dated revision to the same file — do not rewrite history above it:

- What the pipeline changed about the plan, and why.
- Any decision the Reviewer overturned or flagged.
- New open questions the implementation surfaced.

The template carries a stub for this section.
