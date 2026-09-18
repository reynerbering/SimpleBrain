# Frontmatter Contract

> **Single source of truth.** Scope: **travels** — design docs and tickets are authored from code repos too, and they must carry valid frontmatter.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

The Bases in `wiki/design-docs.base` and `tickets/tickets.base` read these properties. A missing property means the note silently drops out of a view — so treat them as required, not decorative.

| Property | Applies to | Values |
| --- | --- | --- |
| `type` | both | `design-doc` or `ticket` |
| `ticket` | both | a real Jira key — see [tickets.md](tickets.md) |
| `team` | both | `CBS` or `AS` |
| `status` | design doc | one of the seven in [Design doc `status`](#design-doc-status) below |
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

## Design doc `status`

Seven values. **`status` answers "how far along is this". The folder answers "is it finished".** The
two meet at exactly one step: `in review` is the first value that lives in `/wiki`.

| `status` | Means | Folder |
| --- | --- | --- |
| `raw` | Captured. No Phase 1 session has run. | `/in-progress/<TEAM>/` |
| `grilling` | Phase 1 underway — decisions not settled, or reopened. | `/in-progress/<TEAM>/` |
| `decided` | Phase 1 complete, every `OPEN QUESTION` cleared, Phase 2 unblocked. | `/in-progress/<TEAM>/` |
| `building` | Phase 2 running — branch cut, pipeline in flight. | `/in-progress/<TEAM>/` |
| `in review` | Ready to merge, or in approval. | `/wiki/<TEAM>/` |
| `implemented` | Merged. | `/wiki/<TEAM>/` |
| `superseded` | Replaced or abandoned. Reachable from any point. | `/wiki/<TEAM>/` |

- **There is no `in progress` value any more.** It restated the folder and said nothing else. `raw`,
  `grilling`, `decided` and `building` all mean "in progress" — they say *which part*.
- **Setting `in review` and moving the file to `/wiki/<TEAM>/` are the same event.** Do both or neither.
  That move also drops [`later` and `priority`](workflow.md#when-the-flag-comes-off).
- **`grilling` is the value to go back to** when a settled decision reopens — `decided` is not a
  ratchet. CBS-4646 did exactly this on 2026-09-18.
- **`status` is unrelated to `later`.** A doc can be `building` and parked, or `raw` and parked. One is
  progress, the other is attention.

⚠️ The **Not yet implemented** view is `status != "implemented"`, so `superseded` docs show up in it.
That predates this vocabulary and is left as-is; the fix is a second filter clause if it ever bites.

## The Bases that consume this

| Base | Views |
| --- | --- |
| `wiki/design-docs.base` | By repo, By team, By status, Not yet implemented, **Later** |
| `tickets/tickets.base` | By status, By team, By repo |

A Base is a saved live query that groups notes without moving them into folders. A doc touching three repos shows up under all three.

**Bases filter on properties, not note bodies.** So "Not yet implemented" is `status != implemented` — it is *not* a list of docs carrying an `OPEN QUESTION` marker, and no view can be. To find real open questions, search the vault for `OPEN QUESTION`.
