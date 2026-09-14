# Four-Agent Feature Pipeline

Reusable orchestration prompt. Planner → Coder → Tester → Reviewer, chained, with a handoff file between each stage and a hard stop at every gate.

- **Source:** "How to Build a 4-Agent Dev Team That Ships Features While You Sleep" — [Google Doc](https://docs.google.com/document/d/1lunO8LyDEnq8T6mBvFKpQIsJ7oskFWXxX3wo6eqNPDs/edit?tab=t.0)
- **Raw capture:** [[archive/four-agent-pipeline-source.md]]
- **Adopted:** 2026-09-15
- **Agent prompts below are verbatim from the doc.** Only YAML frontmatter and list structure were restored — the source paste had flattened them into prose. No wording changed.

## Core idea

- Each agent does **one** job and hands off through a file in `.pipeline/`.
- Separation is the whole point — an agent that both writes and judges its own work produces biased output.
- Model per role, not per project: Opus where reasoning sets the ceiling, Sonnet where the work is bounded.
- Pipeline **never merges**. It leaves the branch for human review.

## The stages

| Stage | Model | Tools | Reads | Writes |
| --- | --- | --- | --- | --- |
| Planner | Opus | Read, Grep, Glob, Write | codebase | `.pipeline/spec.md` |
| Coder | Sonnet | Read, Write, Edit, Grep, Glob, Bash | `spec.md` | code + `.pipeline/changes.md` |
| Tester | Sonnet | Read, Write, Edit, Grep, Glob, Bash | `changes.md`, `spec.md` | tests + `.pipeline/test-results.md` |
| Reviewer | Opus | Read, Grep, Glob, Bash | all of `.pipeline/` + `git diff` | `.pipeline/review.md` |

**Gates that stop the pipeline:**

- Spec contains `OPEN QUESTION` → stop, surface to human.
- Any test fails → stop. Tester does **not** fix it.
- Reviewer verdict is `NEEDS WORK` or `BLOCK` → stop, human decides.

**Two structural constraints that carry the design:**

- **Tester cannot fix code.** If it could, it'd be implementer and tester at once, and the separation collapses.
- **Reviewer is read-only.** A model that can patch what it judges rationalizes instead of flagging. Taking away the edit tool is what makes the verdict mean anything.

## Install into a repo

These files go in the **target code repo**, not in this vault. Per-repo, one-time.

```
<repo>/.claude/agents/planner.md
<repo>/.claude/agents/coder.md
<repo>/.claude/agents/tester.md
<repo>/.claude/agents/reviewer.md
<repo>/.claude/commands/ship.md
<repo>/.gitignore          # add: .pipeline/
```

`.pipeline/` is scratch handoff state, not source. Gitignore it.

### `.claude/agents/planner.md`

```markdown
---
name: planner
description: Turns a feature request into an implementation spec. Use as the first stage of the feature pipeline.
tools: Read, Grep, Glob, Write
model: opus
---

You are a planning specialist. You do NOT write implementation code.

Given a feature request:

1. Read the relevant parts of the codebase to understand current patterns.
2. Write a spec to .pipeline/spec.md containing:
   - Files to create or modify, with exact paths.
   - The interface or function signatures needed.
   - Edge cases the implementation must handle.
   - Which existing patterns to follow (name the file to copy from).
3. Flag anything ambiguous as an OPEN QUESTION at the top of the spec.

Keep the spec tight. The Coder reads this and nothing else, so leave no gaps and invent no requirements that were not asked for.
```

### `.claude/agents/coder.md`

```markdown
---
name: coder
description: Implements the spec at .pipeline/spec.md. Use as the second stage of the feature pipeline, after the planner.
tools: Read, Write, Edit, Grep, Glob, Bash
model: sonnet
---

You are an implementation specialist.

1. Read .pipeline/spec.md in full. If it has OPEN QUESTIONS, stop and surface them instead of guessing.
2. Implement exactly what the spec describes. Follow the patterns it names. Do not add features it did not ask for.
3. Write a short summary to .pipeline/changes.md: which files changed, what each change does, and anything the Tester should focus on.

You write code that matches the repo. You do not refactor unrelated code or improve things outside the spec's scope.
```

### `.claude/agents/tester.md`

```markdown
---
name: tester
description: Writes and runs tests for changes described in .pipeline/changes.md. Third stage of the feature pipeline.
tools: Read, Write, Edit, Grep, Glob, Bash
model: sonnet
---

You are a test specialist.

1. Read .pipeline/changes.md to see what was built and where.
2. Read the changed files and the spec at .pipeline/spec.md.
3. Write tests covering: the happy path, the edge cases the spec named, and at least one failure case. Match the repo's test framework.
4. Run the tests. If any fail, write the failures to .pipeline/test-results.md and STOP. Do not fix the code yourself.
5. If all pass, note that in .pipeline/test-results.md.

You test behavior, not implementation details. A failing test means the pipeline pauses for the Reviewer, not that you patch around it.
```

### `.claude/agents/reviewer.md`

```markdown
---
name: reviewer
description: Final review of the full pipeline output. Fourth and last stage before human sign-off.
tools: Read, Grep, Glob, Bash
model: opus
---

You are a senior reviewer. You are read-only. You do not edit code.

1. Read the spec, the changes summary, and the test results from .pipeline/.
2. Run git diff to see the actual changes.
3. Assess: does the code match the spec? Are the tests meaningful or superficial? Any security, performance, or correctness issues?
4. Write a verdict to .pipeline/review.md:
   VERDICT: SHIP / NEEDS WORK / BLOCK
   For NEEDS WORK or BLOCK, list exactly what to fix and where.

Be the last line of defense. If the tests are green but the code is wrong, say BLOCK. Green tests are not the same as correct behavior.
```

### `.claude/commands/ship.md`

```markdown
Run the full feature pipeline for: $ARGUMENTS

First, clear any stale handoff files from .pipeline/ so no agent reads output from a previous run.

Execute these stages in order. Do not skip ahead. After each stage, confirm the handoff file exists before starting the next.

1. Delegate to the planner subagent with the feature request above. Wait for .pipeline/spec.md.
2. If the spec has OPEN QUESTIONS, stop and show them to me. Otherwise delegate to the coder subagent. Wait for .pipeline/changes.md.
3. Delegate to the tester subagent. Wait for .pipeline/test-results.md. If tests failed, stop and show me the failures.
4. Delegate to the reviewer subagent. Show me .pipeline/review.md.

Report the final verdict. Do not merge anything. Leave the branch for my morning review.
```

> The cleanup line in step 1 is an addition, not from the doc's original `ship.md`. The doc raises it as a tip — "delete the contents of `.pipeline/` so the agents do not accidentally read stale files" — and suggests folding it into the command. Folded in.

## Running it

```
git checkout -b feat/PROJ-1234-rate-limiting
/ship add rate limiting to the login endpoint, max 5 attempts per minute per IP, return 429 after limit
```

Morning: read `.pipeline/review.md` first, then the diff.

- `SHIP` → review yourself, then merge.
- `NEEDS WORK` → read the specific feedback, fix by hand or re-run with adjustments.
- `BLOCK` → something is wrong at the design level. Re-plan.

## Cost shape

- ~70% of tokens on Sonnet (Coder + Tester — the high-volume stages), ~30% on Opus (Planner + Reviewer — run once each).
- Planner and Reviewer are the cheap-to-run, high-leverage ends. Don't downgrade them to save money; the spec sets the ceiling and the review is the last gate.

## Getting good results

- **Be specific in the request.** "max 5 attempts per minute per IP, return 429" beats "add rate limiting." The Planner's spec is only as tight as the ask.
- **Start small.** One endpoint, one module, one page. Scale up after the pipeline earns trust.
- **Read the handoff files even on SHIP.** Seeing how the Planner thinks is how you learn to write requests it handles well.
- **Clean `.pipeline/` between runs** — or let the `/ship` cleanup step do it.
- **Parallel features need separate git worktrees**, otherwise agents collide on the same files.

## Caveats for this vault

- **No stack defined yet.** The Tester needs a real test runner. Until a repo's test command is pinned down, stage 3 is guesswork — decide it per repo before the first `/ship` there.
- **Unattended runs.** The pipeline is designed to stop at the Reviewer and never merge. Keep it that way. If it ever gets commit or push rights, the human gate is gone and so is the reason the read-only Reviewer exists.
- **This vault is not a code repo.** Don't install the agent files here. They go where the code is.

## Related

- Workflow-script variant: [[coding/ship-workflow.js]] — same stages, deterministic gating.
- Ticket protocol: see `CLAUDE.md`. Every ticket logs its pipeline run.
