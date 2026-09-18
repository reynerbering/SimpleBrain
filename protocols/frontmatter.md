# Frontmatter Contract

> **Single source of truth.** Scope: **travels** — design docs and tickets are authored from code repos too, and they must carry valid frontmatter.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

The Bases in `wiki/design-docs.base` and `tickets/tickets.base` read these properties. A missing property means the note silently drops out of a view — so treat them as required, not decorative.

| Property | Applies to | Values |
| --- | --- | --- |
| `type` | both | `design-doc` or `ticket` |
| `ticket` | both | a real Jira key — see [tickets.md](tickets.md) |
| `team` | both | `CBS` or `AS` |
| `status` | design doc | `decided`, `in progress`, `implemented`, `superseded` |
| `status` | ticket | the Jira status string |
| `source` | ticket | `jira` or `unverified` |
| `repos` | both | list of **exact on-disk folder names** from the README repo tables |
| `later` | design doc | date it was **last** parked. Present only while flagged — see [workflow.md](workflow.md#finish-it-later--the-later-flag) |
| `priority` | design doc | `high`, `medium`, `low`. Set together with `later`; meaningless without it |
| `grilled` | design doc | date of the Phase 1 session |
| `updated` | both | date of the last edit — bump it every session |

- **`later` and `priority` are the only optional pair.** Absent means not parked. Both are **dropped** when the doc moves to `/wiki/<TEAM>/`, so nothing in `/wiki` carries a `later`.
- **`repos` is a list, always** — even for a single repo. A string breaks the By-repo grouping.
- Use the on-disk folder name verbatim: `CoreAPI` (PascalCase), `ea-distribution-update`, `apply-with-jobtarget-api`. Not the GitLab path, not the display name.
- A repo not listed in the [`README.md`](../README.md) repo tables has no assigned team. Ask before inventing one.

## The Bases that consume this

| Base | Views |
| --- | --- |
| `wiki/design-docs.base` | By repo, By team, By status, Not yet implemented, **Later** |
| `tickets/tickets.base` | By status, By team, By repo |

A Base is a saved live query that groups notes without moving them into folders. A doc touching three repos shows up under all three.

**Bases filter on properties, not note bodies.** So "Not yet implemented" is `status != implemented` — it is *not* a list of docs carrying an `OPEN QUESTION` marker, and no view can be. To find real open questions, search the vault for `OPEN QUESTION`.
