# Four-Agent Feature Pipeline

Reusable orchestration prompt. Planner → Coder → Tester → Reviewer, chained, with a handoff file between each stage and a hard stop at every gate.

- **Source:** "How to Build a 4-Agent Dev Team That Ships Features While You Sleep" — [Google Doc](https://docs.google.com/document/d/1lunO8LyDEnq8T6mBvFKpQIsJ7oskFWXxX3wo6eqNPDs/edit?tab=t.0)
- **Raw capture:** [[archive/four-agent-pipeline-source.md]]
- **Live files:** `coding/ship/` — the real agents and command. This note explains them; it does not duplicate them.
- **Adopted:** 2026-09-15

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
- Any test fails, or no test runner can be identified → stop. Tester does **not** fix it.
- Reviewer verdict is `NEEDS WORK` or `BLOCK` → stop, human decides.

**Two structural constraints that carry the design:**

- **Tester cannot fix code.** If it could, it'd be implementer and tester at once, and the separation collapses.
- **Reviewer is read-only.** A model that can patch what it judges rationalizes instead of flagging. Taking away the edit tool is what makes the verdict mean anything.

## Setup — per machine

The pipeline is installed **globally**, at the user level. `/ship` then works in every repo with nothing checked into any of them.

The vault is the source of truth. `coding/ship/` holds the real files; the installer copies them into `~/.claude`.

```powershell
git pull
.\coding\ship\install.ps1
```

Then restart Claude Code. That's the whole setup, and it's the same on both machines.

- `install.ps1 -Check` — dry run, shows what would change and touches nothing.
- Re-run after any `git pull` that touches `coding/ship/`. Unchanged files are skipped, so it's cheap and safe to run whenever.
- The installer also sets up the global gitignore for `.pipeline/` (see below). Skip with `-SkipGitIgnore`.

**What it installs:**

```
coding/ship/agents/ship-planner.md    ->  ~/.claude/agents/ship-planner.md
coding/ship/agents/ship-coder.md      ->  ~/.claude/agents/ship-coder.md
coding/ship/agents/ship-tester.md     ->  ~/.claude/agents/ship-tester.md
coding/ship/agents/ship-reviewer.md   ->  ~/.claude/agents/ship-reviewer.md
coding/ship/commands/ship.md          ->  ~/.claude/commands/ship.md
```

**Editing the pipeline:** change the file in `coding/ship/`, re-run the installer, commit, push. Never edit `~/.claude` directly — the next install silently overwrites it and the change is lost. Copies flow one way only, vault → machine.

**`.pipeline/` gets written into whatever repo you run in.** Scratch handoff state, not source. The installer handles this once per machine:

```
git config --global core.excludesFile ~/.gitignore_global
echo ".pipeline/" >> ~/.gitignore_global
```

Without it, every repo you ship in grows an untracked `.pipeline/` in `git status`.

## Deviations from the source doc

The four agent prompts are **verbatim** from the doc — only YAML frontmatter and list structure were restored, since the source paste had flattened them into prose. Everything below is an addition, and all of it exists because the doc assumed a per-repo install and this one is global.

- **Agents renamed `ship-*`.** Bare names like `coder` would sit in every project and be silently shadowed by any repo defining its own. Prefixing keeps the pipeline self-contained.
- **Tester must refuse to guess a test runner.** A global pipeline meets repos it knows nothing about. It now reports `no test runner identified` and stops. A guessed green is worse than no test at all.
- **Reviewer's read-only rule restated as an explicit git prohibition.** It has Bash, so "read-only" alone doesn't stop it reaching git.
- **Preflight branch guard.** The doc makes branching a human step. A global command will eventually get fired on `main`; the guard makes that a stop instead of a mess.
- **`.pipeline/` cleanup in preflight.** The doc raises it as a tip and suggests folding it into the command. Folded in.
- **Empty-argument check.** Without it, `/ship` with no argument invents a feature from whatever was being discussed.
- **Explicit "do not do the stage work yourself."** The orchestrator has full tools and will otherwise sometimes just implement the thing, collapsing the separation the whole design rests on.
- **Ticket reminder.** Wires the pipeline back to the vault's ticket protocol.

## Running it

```
git checkout -b PROJ-1234-rate-limiting
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

- **Test runner resolution.** The Tester resolves in strict order: the repo's own `CLAUDE.md` / `AGENTS.md` / `README.md` → stack detection (.NET via `.sln`/`.csproj`, Node/TS via `package.json`) → stop. Ambiguity is a stop, not a guess: mixed stacks, monorepo without a clear root, or a missing `test` script all halt stage 3. Stack shapes live in the vault [README](../README.md); a repo's own `CLAUDE.md` always wins over them.
- **Env failures are not test failures.** A missing SDK or uninstalled deps stops the pipeline and is reported as environmental, not as the code being wrong. Don't read that as a `BLOCK`.
- **Unattended runs.** The pipeline stops at the Reviewer and never merges. Keep it that way. If it ever gets commit or push rights, the human gate is gone and so is the reason the read-only Reviewer exists.
- **Global means global.** The `ship-*` agents are visible in every project, including this vault. Harmless — they only activate when `/ship` delegates to them — but a change to `coding/ship/` changes every repo's pipeline on the next install.
- **Work vs personal machine.** Both run the same install. If the work machine ever needs different behaviour (different models, stricter gates), fork the file in `coding/ship/` rather than hand-editing `~/.claude` there — otherwise the next install wipes it.
- **Untested.** Installed 2026-09-15, not yet run end-to-end on a real repo. First run should be a small bounded feature on a repo whose test command you already know.

## Related

- **Phase 1 comes first.** This pipeline is Phase 2 of the two-phase workflow — it expects a design doc named `<KEY>-<slug>.md` — normally in `/in-progress/<TEAM>/` — produced by a `/grill-me` session. Feed that doc to the Planner, not a one-line ask. See the [README](../README.md) and `CLAUDE.md`.
- Workflow-script variant: [[coding/ship-workflow.js]] — same stages, gates enforced as code rather than instructions.
- Ticket protocol: see `CLAUDE.md`. Every ticket logs its pipeline run.
