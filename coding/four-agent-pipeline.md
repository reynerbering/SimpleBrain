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

## Install — global, not per-repo

Installed once at the **user level**. `/ship` works in every repo; nothing is checked into any of them.

```
~/.claude/agents/ship-planner.md
~/.claude/agents/ship-coder.md
~/.claude/agents/ship-tester.md
~/.claude/agents/ship-reviewer.md
~/.claude/commands/ship.md
```

**Installed 2026-09-15.** The blocks below are the source of truth — if a file at `~/.claude` drifts, restore it from here.

**Agents are named `ship-*`, not `planner`/`coder`/etc.** Deviation from the doc, deliberate: these are global now, so bare names like `coder` would sit in every project and be silently shadowed by any repo that defines its own. Prefixing keeps the pipeline self-contained.

**`.pipeline/` still gets written into whatever repo you run in.** It's scratch handoff state, not source. Global ignore, once:

```
git config --global core.excludesFile ~/.gitignore_global
echo ".pipeline/" >> ~/.gitignore_global
```

Otherwise every repo you ship in grows an untracked `.pipeline/` that shows up in `git status`.

### `~/.claude/agents/ship-planner.md`

```markdown
---
name: ship-planner
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

### `~/.claude/agents/ship-coder.md`

```markdown
---
name: ship-coder
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

### `~/.claude/agents/ship-tester.md`

```markdown
---
name: ship-tester
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

Determining the test command: infer it from the repo itself — package.json scripts, Makefile, pyproject.toml, go.mod, the CI config, or an existing test directory's conventions. If you cannot determine how to run the suite with confidence, write "no test runner identified" to .pipeline/test-results.md and STOP. Do not invent a command and do not report a pass you did not observe.
```

> The final paragraph is an addition, not from the doc. A global pipeline meets repos it knows nothing about, so the Tester needs an explicit instruction to refuse rather than guess a runner. A guessed green is worse than no test.

### `~/.claude/agents/ship-reviewer.md`

```markdown
---
name: ship-reviewer
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

You do not stage, commit, merge, or push. Your only output is the verdict file.
```

> The final line is an addition, not from the doc. It restates the read-only constraint as an explicit prohibition, since the Reviewer has Bash and could otherwise reach git.

### `~/.claude/commands/ship.md`

```markdown
---
description: Run the four-agent feature pipeline (plan → code → test → review) on the current repo
argument-hint: <feature request>
---

Run the full feature pipeline for: $ARGUMENTS

If $ARGUMENTS is empty, stop and ask what to build. Do not infer a feature from the conversation.

## Preflight

1. Confirm the working directory is a git repo. If not, stop.
2. Check the current branch. If it is `main`, `master`, `develop`, or `trunk`, STOP and tell me — offer a branch name derived from the request (e.g. `feat/<slug>`, or `feat/<JIRA-KEY>-<slug>` if the request names a ticket) and wait for my go-ahead. Never run the pipeline on a shared branch.
3. Delete the contents of `.pipeline/` so no agent reads stale output from a previous run. Recreate the directory empty.
4. If `.pipeline/` is not covered by this repo's `.gitignore` or your global excludes, say so once. It is scratch handoff state and should not be committed.

## Stages

Execute in order. Do not skip ahead. After each stage, confirm the handoff file exists before starting the next. Do not do any of the stage work yourself — each stage is delegated.

1. Delegate to the **ship-planner** subagent with the feature request above. Wait for `.pipeline/spec.md`.
2. Read the spec. If it contains OPEN QUESTIONS, STOP and show them to me. Otherwise delegate to the **ship-coder** subagent. Wait for `.pipeline/changes.md`.
3. Delegate to the **ship-tester** subagent. Wait for `.pipeline/test-results.md`. If any test failed, or the tester reported no test runner identified, STOP and show me the details. Do not fix the code and do not proceed to review.
4. Delegate to the **ship-reviewer** subagent. Wait for `.pipeline/review.md`. Show it to me.

## Rules

- A stage gate that trips ends the run. Do not retry, work around, or "fix it quickly" yourself — surface it and stop.
- Do not stage, commit, merge, or push anything at any point.
- Report the final verdict and where the handoff files are. Leave the branch for my review.

## After the run

If the request names a Jira key, remind me to log the run in `tickets/<KEY>.md` in the SimpleBrain vault — verdict, what the reviewer flagged, and any gate that tripped.
```

**Deviations from the doc's `ship.md`, all deliberate:**

- **Preflight branch guard.** The doc says "create a new branch" as a human step before running. A global command will eventually get fired on `main` by accident; the guard makes that a stop instead of a mess.
- **`.pipeline/` cleanup in preflight.** The doc raises it as a tip and suggests folding it into the command. Folded in.
- **Empty-argument check.** Without it, `/ship` with no argument invents a feature from whatever was being discussed.
- **Explicit "do not do the stage work yourself."** The orchestrator has full tools and will otherwise sometimes just implement the thing, collapsing the separation the whole design rests on.
- **Ticket reminder.** Wires the pipeline back to the vault's ticket protocol.

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

## Caveats

- **Test runner per repo.** The Tester executes a real suite. It's instructed to refuse rather than guess, so an unfamiliar repo will stop at stage 3 with "no test runner identified" — that's the correct failure. Pin the command in that repo's `CLAUDE.md` and it stops recurring.
- **Unattended runs.** The pipeline stops at the Reviewer and never merges. Keep it that way. If it ever gets commit or push rights, the human gate is gone and so is the reason the read-only Reviewer exists.
- **Global means global.** The `ship-*` agents are visible in every project, including this vault. Harmless — they only activate when `/ship` delegates to them — but it does mean a change to `~/.claude/agents/` changes every repo's pipeline at once. This note is the backup.
- **Untested.** Installed 2026-09-15, not yet run end-to-end on a real repo. First run should be a small bounded feature.

## Related

- Workflow-script variant: [[coding/ship-workflow.js]] — same stages, deterministic gating.
- Ticket protocol: see `CLAUDE.md`. Every ticket logs its pipeline run.
