# The Two-Phase Workflow

> **Single source of truth.** Scope: **travels** — applies in every repo, not just the vault.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

All coding work runs in two phases, in order. Never start Phase 2 without a Phase 1 document.

| Phase      | What happens                                                         | Tool                                         | Output                                       |
| ---------- | -------------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| 1 — Decide | Relentless interview until Neru and the agent share an understanding | `/grill-me`, `/grill-with-docs`, `/grilling` | `/in-progress/<TEAM>/<KEY>-<slug>.md`        |
| 2 — Build  | Planner → Coder → Tester → Reviewer                                  | `/ship`                                      | code on a branch + `/tickets/<TEAM>/<KEY>.md` entry |

- **Phase 1 is not optional for non-trivial work.** If asked to implement something with no design doc, say so and offer to grill it first.
- **Phase 2 reads Phase 1.** Hand the Planner the design doc, not a one-line restatement of the ask.
- **The document is the contract.** If the pipeline contradicts a decision in it, that is a stop and a revision — not a silent override.

## Phase 1 — Grill it until it's decided

Nothing gets implemented before the thinking is finished.

1. **Start from the work.** Pull the ticket detail from Jira, or start from a raw idea that just showed up.
2. **Grill it.** Run one of the Matt Pocock grilling skills:
   - `/grill-me` — the standard relentless interview over a plan or design.
   - `/grill-with-docs` — same interview, but also produces ADRs and a glossary as it goes, via `/domain-modeling`. Use this when the work introduces new domain vocabulary.
   - `/grilling` — the underlying skill both of the above run.
3. **Answer one question at a time.** The skill walks the decision tree branch by branch and waits. Facts it looks up itself; the decisions are Neru's.
4. **Land on a shared understanding.** The output is one big document that the agent and Neru actually agreed on — not a summary it wrote at him.
5. **File it** per [the design doc protocol](design-docs.md).

## Phase 2 — Ship it through the pipeline

The agreed document is the input. Now it gets built.

1. **Branch for the ticket** — see [Branch and worktree naming](#branch-and-worktree-naming) below.
   Never on a shared branch.
2. **Run `/ship`** — the four-agent pipeline. Stages, models, gates, and handoff files are in [`coding/four-agent-pipeline.md`](../coding/four-agent-pipeline.md); `coding/ship-workflow.js` is the Workflow-script variant of the same thing.
3. **Feed the Planner the design doc**, not a one-line ask. Phase 1 exists so the spec starts from settled decisions.
4. **Read `.pipeline/review.md` first**, then the diff. The pipeline never merges — Neru is the final gate.
5. **Fold the outcome back in.** Anything the pipeline changed, flagged, or forced a rethink on goes back into the same design doc as a dated revision.

## Branch and worktree naming

The single source for how Phase 2 work is named on disk and in git.

| Thing | Pattern | Example |
| --- | --- | --- |
| Branch | `<JIRA-KEY>-<slug>` | `CBS-4436-v2-posting-analytics-wrap` |
| Isolated worktree | `<repo-folder>-<JIRA-KEY>` beside the repo | `C:\JT Repositories\CoreAPI-CBS-4436` |

- **No `feat/` prefix.** The key leads. Verified against `CoreAPI`'s live open MRs on 2026-09-18 —
  `CBS-4643-ofccp-getjobs-param-validation`, `CBS-4548-replaceuser-firstordefault`. A branch named
  `feat/CBS-...` does not match what the team does and will not group with the rest.
- **`<slug>` is the design doc's slug**, so `<KEY>-<slug>.md`, the branch and the worktree all
  carry the same name. One string to search for across the vault, git and Jira.
- ⚠️ **Check the repo's real convention before creating the branch** — `git ls-remote --heads origin`,
  or list its open MRs. This protocol travels, but **a repo's own convention outranks it inside that
  repo** (see the hard rules in [`CLAUDE.md`](../CLAUDE.md)). This very rule was written the wrong way
  round first: the vault said `feat/<KEY>-<slug>`, `CoreAPI` has never used a prefix, and the vault
  pattern got applied without looking. Look.
- **Never branch from a shared branch's working tree while it is dirty.** Check the repo's default
  branch with `git symbolic-ref refs/remotes/origin/HEAD` — on `CoreAPI` it is **`develop`**, not
  `main`, so an MR targets `develop`.
- **Use a separate worktree when the main checkout is not clean and on the right branch:**

  ```
  git worktree add -b <KEY>-<slug> "<repo>-<KEY>" <base-commit>
  ```

  Base it on the **exact commit the design doc cites**, not on whatever `HEAD` happens to be.

**Why the worktree, not just a branch.** Switching branches carries uncommitted changes with you. If
the main checkout holds unrelated in-flight work, that work lands in the pipeline's diff, goes to the
Reviewer as if it were part of the feature, and gets swept into the commit. A worktree is a separate
directory, so the other branch's dirty tree is untouchable — verify it with `git status` in the
original checkout after the run.

**Commit named files, never `git add -A`.** A repo can carry local-only edits that must never be
committed — on `CoreAPI`, `CoreAPI.TestFramework/CoreApiTestFramework.cs` (`jtmssql` -> `localhost`) is
a documented local setup step that would point CI at localhost. Stage the files the change actually
touched and check `git status` before committing.

## Where work lives

Two places. A design doc makes **one** move in its life, and Neru triggers it.

| Folder | Holds | Layout |
| --- | --- | --- |
| `/in-progress/<TEAM>/` | Every design doc that is not done — worked on *or* parked | `CBS/`, `AS/` |
| `/wiki/<WEEK>/<TEAM>/` | Done, filed under the working week it was marked | one folder per week, `CBS/` and `AS/` inside |

- **Everything starts and stays in `/in-progress/<TEAM>/`** — a raw idea, a Phase 1 grilling, a Phase 2
  pipeline run, something parked for a month. Parking does not move a file.
- **Nothing moves on its own.** Not a merge, not a green pipeline, not `status: decided`. See below.
- `/wiki/repos/` is outside this lifecycle — repo memory is never "in progress". See
  [the repo memory protocol](repo-memory.md).
- **`/tickets/<TEAM>/<KEY>.md` never moves.** A ticket log is not work-in-flight; it lives in `/tickets`
  from the first entry to the last. The team folder there is organisation, nothing more.

### Done — filing into the week

**Only Neru marks a doc done.** Merged, shipped, approved, abandoned — none of those set it. He says
the word or it is not done. When he does:

1. **Set `status: done`.**
2. **Drop `later` and `priority`** if present.
3. **Move the file to `/wiki/<WEEK>/<TEAM>/`**, creating the folders if they do not exist.

`<WEEK>` is the **Monday of the working week he said it**, as `YYYY-MM-DD`. Not the week the work
happened — the week it was marked. Compute it, never count back by hand:

```bash
date -d "-$(( $(date +%u) - 1 )) days" +%Y-%m-%d
```

- **The week is Mon–Fri.** Neru does not work weekends, so a doc marked on a Saturday or Sunday folds
  back into the week that just ended — which is what the command above already does. Verified
  2026-09-19: Saturday → `2026-09-14`; Sunday the 20th → `2026-09-14`; Monday the 14th → itself.
- **Team folders are created lazily.** A week with only CBS work has no `AS/` folder in it.
- A done doc is still amendable. Appending a dated revision to something in `/wiki` does not move it
  back, and does not re-date its week folder.

### "Finish it later" — the `later` flag

`later` marks a doc as a **priority to pick back up**. It is a subset of `/in-progress/`: same folder,
still unfinished, just flagged and ranked.

When Neru says **finish it later**:

1. **Append a dated handoff section to the bottom of the file.** Never rewrite what is above it. This
   is the substance of the instruction — the flag is the easy half.
2. **Set two properties:**

   ```yaml
   later: <YYYY-MM-DD>        # the date it was parked
   priority: high             # high | medium | low
   ```

3. **Ask for the priority if Neru did not give one.** Never infer it from how urgent the work sounds —
   that is inventing a fact.
4. **`status` does not change.** Parked is a flag, not a stage.

The handoff section:

```markdown
## <YYYY-MM-DD> — parked

**Where it stands:** <current state, one or two lines>

**Decided this session:**
- <decision> — <the reasoning, in Neru's own words>

**Still open:**
- OPEN QUESTION: <what is genuinely unresolved>

**Pick up by:** <the literal next action>
```

- **Every decision and detail the session actually reached goes in.** The whole point is that the next
  session starts from the settled position instead of re-deriving the conversation. A thin summary
  defeats it.
- `OPEN QUESTION` markers carry their usual meaning — [the Planner stops on them](design-docs.md).
- Run `date` for the heading. Never back-fill it.

### When the flag comes off

- **Only when Neru marks the doc done.** A session picking it back up leaves `later` and `priority`
  alone — the flag survives being worked on, so the Later view is not quietly emptied by activity.
- **Re-parking overwrites `later` with the new date** and re-asks the priority. The property means
  "when it was *last* parked", which is what makes oldest-first a useful order.

## Where things end up

| Artifact | Lives in | Holds |
| --- | --- | --- |
| Design doc | `/in-progress/<TEAM>/` until Neru marks it done, then `/wiki/<WEEK>/<TEAM>/` — named `<KEY>-<slug>.md` | Every decision + reasoning, before and after implementation |
| Ticket log | `/tickets/<TEAM>/<KEY>.md` | Dated activity: what was done, what was touched, pipeline verdict, blockers |
| Pipeline handoffs | `.pipeline/` in the repo | Scratch. Gitignored. Not a record. |

The design doc owns the **decisions**. The ticket owns the **log**. They link to each other and neither repeats the other.

**Link by bare name — `[[CBS-1234-rate-limiting]]`, not `[[wiki/CBS-1234-rate-limiting.md]]`.** A design
doc changes folder when it is marked done, so a path-form link breaks on the one move that matters.

**Ticket and design-doc files always live in the vault**, even when the code work happens in a repo elsewhere. Never scatter them into the repo being worked on.
