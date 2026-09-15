# The Two-Phase Workflow

> **Single source of truth.** Scope: **travels** — applies in every repo, not just the vault.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

All coding work runs in two phases, in order. Never start Phase 2 without a Phase 1 document.

| Phase      | What happens                                                         | Tool                                         | Output                                       |
| ---------- | -------------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------- |
| 1 — Decide | Relentless interview until Neru and the agent share an understanding | `/grill-me`, `/grill-with-docs`, `/grilling` | `/wiki/<KEY>-<slug>.md`                      |
| 2 — Build  | Planner → Coder → Tester → Reviewer                                  | `/ship`                                      | code on a branch + `/tickets/<KEY>.md` entry |

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

1. **Branch for the ticket** — `feat/CBS-1234-<slug>`. Never on `main`.
2. **Run `/ship`** — the four-agent pipeline. Stages, models, gates, and handoff files are in [`coding/four-agent-pipeline.md`](../coding/four-agent-pipeline.md); `coding/ship-workflow.js` is the Workflow-script variant of the same thing.
3. **Feed the Planner the design doc**, not a one-line ask. Phase 1 exists so the spec starts from settled decisions.
4. **Read `.pipeline/review.md` first**, then the diff. The pipeline never merges — Neru is the final gate.
5. **Fold the outcome back in.** Anything the pipeline changed, flagged, or forced a rethink on goes back into the same wiki doc as a dated revision.

## Where things end up

| Artifact | Lives in | Holds |
| --- | --- | --- |
| Design doc | `/wiki/<KEY>-<slug>.md` | Every decision + reasoning, before and after implementation |
| Ticket log | `/tickets/<KEY>.md` | Dated activity: what was done, what was touched, pipeline verdict, blockers |
| Pipeline handoffs | `.pipeline/` in the repo | Scratch. Gitignored. Not a record. |

The wiki doc owns the **decisions**. The ticket owns the **log**. They link to each other and neither repeats the other.

**Ticket and design-doc files always live in the vault**, even when the code work happens in a repo elsewhere. Never scatter them into the repo being worked on.
