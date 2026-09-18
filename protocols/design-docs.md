# Design Doc Protocol

> **Single source of truth.** Scope: **travels** — design docs are authored in the vault even when the code work happens in a repo elsewhere.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

**Location:** `<KEY>-<slug>.md` — e.g. `CBS-1234-rate-limiting.md`. **Which folder it sits in depends on
where the work has got to** — `/in-progress/<TEAM>/`, `/later/`, or `/wiki/<TEAM>/`. That lifecycle is
[the workflow protocol](workflow.md#where-work-lives), the only copy. New docs start in `/in-progress/<TEAM>/`.

- Work that started as a raw idea with no ticket uses a bare kebab-case slug (`agent-memory-compaction.md`). Rename it through Obsidian once a key exists.
- **Link to a design doc by bare name** — `[[CBS-1234-rate-limiting]]`. A path-form link breaks the moment the doc is parked or resumed.
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

**Before marking a doc `status: decided`, run `grep -rn "OPEN QUESTION" in-progress/ later/ wiki/`** and clear every marker
that has actually been answered.

- Writing the Decisions section does **not** remove the markers. A doc can end up asserting
  "Q1 decided" and "Q1 asked, unanswered" at the same time — and would then **halt the Planner**
  ([`coding/four-agent-pipeline.md`](../coding/four-agent-pipeline.md)) on a question that is closed.
- No Base can catch this: Bases filter on properties, not note bodies
  ([frontmatter.md](frontmatter.md)). The grep is the only check.
- Leave the marker only on what is genuinely unresolved — unrun gates, undecided branches. Point
  everything else at the Decisions section rather than restating it.

## After the pipeline runs

Append a dated revision to the same file — do not rewrite history above it:

- What the pipeline changed about the plan, and why.
- Any decision the Reviewer overturned or flagged.
- New open questions the implementation surfaced.

The template carries a stub for this section.
