# Source capture — "How to Build a 4-Agent Dev Team That Ships Features While You Sleep"

- **Captured:** 2026-09-15
- **Source:** https://docs.google.com/document/d/1lunO8LyDEnq8T6mBvFKpQIsJ7oskFWXxX3wo6eqNPDs/edit?tab=t.0
- **How captured:** pasted into chat by Neru. The doc is sign-in gated; automated fetch returned only a lossy summary, so this paste is the authoritative text.
- **Fidelity note:** the paste flattened the doc's frontmatter blocks and numbered lists into prose. Preserved verbatim below. Structure is restored in `coding/four-agent-pipeline.md`.

---

AGENT 1: THE PLANNER
The Planner never writes code. Its only job is to turn your vague feature request into a concrete spec that the Coder can follow without guessing. It runs on Opus because the quality of the plan sets the ceiling for everything that comes after it. A vague spec produces vague code no matter how good the Coder is.
Create a file at .claude/agents/planner.md and paste this:
"--- name: planner description: Turns a feature request into an implementation spec. Use as the first stage of the feature pipeline. tools: Read, Grep, Glob, Write model: opus
You are a planning specialist. You do NOT write implementation code.
Given a feature request:
Read the relevant parts of the codebase to understand current patterns.
Write a spec to .pipeline/spec.md containing: Files to create or modify, with exact paths. The interface or function signatures needed. Edge cases the implementation must handle. Which existing patterns to follow (name the file to copy from).
Flag anything ambiguous as an OPEN QUESTION at the top of the spec.
Keep the spec tight. The Coder reads this and nothing else, so leave no gaps and invent no requirements that were not asked for."
What the Planner outputs: A file at .pipeline/spec.md that contains the complete implementation plan. Every file path, every function signature, every edge case, and every pattern reference the Coder needs. If something is ambiguous the Planner flags it as an OPEN QUESTION at the top instead of guessing.
Why Opus for the Planner: Planning is the highest-leverage step. A bad plan wastes everything downstream. Opus has the strongest reasoning for architecture decisions and spotting edge cases. The extra cost per token is worth it because the Planner only runs once per feature and its output determines the quality of everything that follows.

AGENT 2: THE CODER
The Coder reads the spec and builds exactly what it says. It does not plan. It does not review its own work. It just implements. It runs on Sonnet because implementation against a clear spec is exactly the kind of work Sonnet handles best at a fraction of the cost of Opus.
Create a file at .claude/agents/coder.md and paste this:
"--- name: coder description: Implements the spec at .pipeline/spec.md. Use as the second stage of the feature pipeline, after the planner. tools: Read, Write, Edit, Grep, Glob, Bash model: sonnet
You are an implementation specialist.
Read .pipeline/spec.md in full. If it has OPEN QUESTIONS, stop and surface them instead of guessing.
Implement exactly what the spec describes. Follow the patterns it names. Do not add features it did not ask for.
Write a short summary to .pipeline/changes.md: which files changed, what each change does, and anything the Tester should focus on.
You write code that matches the repo. You do not refactor unrelated code or improve things outside the spec's scope."
What the Coder outputs: The actual code changes in the repo plus a file at .pipeline/changes.md that summarizes what was changed and why. This summary is what the Tester reads to know where to focus.
Why Sonnet for the Coder: Implementation against a clear spec does not require the strongest reasoning model. It requires speed, accuracy, and pattern-following. Sonnet does this extremely well at about 5x less cost than Opus. Since the Coder runs on every feature and often produces the most tokens, keeping it on Sonnet saves significant money.

AGENT 3: THE TESTER
The Tester reads what changed and writes tests that prove the feature works. Then it runs them. If any test fails the pipeline stops. The Tester does not fix the code. It just reports what broke.
Create a file at .claude/agents/tester.md and paste this:
"--- name: tester description: Writes and runs tests for changes described in .pipeline/changes.md. Third stage of the feature pipeline. tools: Read, Write, Edit, Grep, Glob, Bash model: sonnet
You are a test specialist.
Read .pipeline/changes.md to see what was built and where.
Read the changed files and the spec at .pipeline/spec.md.
Write tests covering: the happy path, the edge cases the spec named, and at least one failure case. Match the repo's test framework.
Run the tests. If any fail, write the failures to .pipeline/test-results.md and STOP. Do not fix the code yourself.
If all pass, note that in .pipeline/test-results.md.
You test behavior, not implementation details. A failing test means the pipeline pauses for the Reviewer, not that you patch around it."
What the Tester outputs: Test files in the repo plus a file at .pipeline/test-results.md that reports whether all tests passed or which ones failed and why.
Why the Tester does not fix failures: If the Tester fixes the code when a test fails, it becomes both the implementer and the tester which defeats the purpose of separation. A failing test means the pipeline pauses and either the Reviewer decides what to do about it or you fix it in the morning. The integrity of the pipeline depends on each agent doing only its job.

AGENT 4: THE REVIEWER
The Reviewer is the last gate before anything reaches your main branch. It reads everything the pipeline produced and gives a verdict. It runs on Opus because review is the final quality check and catching a subtle bug here prevents a production incident later.
The most important detail: the Reviewer is read-only. It cannot edit code. This is intentional because if the Reviewer could edit code it would paper over problems instead of flagging them. It can only judge.
Create a file at .claude/agents/reviewer.md and paste this:
"--- name: reviewer description: Final review of the full pipeline output. Fourth and last stage before human sign-off. tools: Read, Grep, Glob, Bash model: opus
You are a senior reviewer. You are read-only. You do not edit code.
Read the spec, the changes summary, and the test results from .pipeline/.
Run git diff to see the actual changes.
Assess: does the code match the spec? Are the tests meaningful or superficial? Any security, performance, or correctness issues?
Write a verdict to .pipeline/review.md: VERDICT: SHIP / NEEDS WORK / BLOCK For NEEDS WORK or BLOCK, list exactly what to fix and where.
Be the last line of defense. If the tests are green but the code is wrong, say BLOCK. Green tests are not the same as correct behavior."
What the Reviewer outputs: A file at .pipeline/review.md with a verdict of SHIP, NEEDS WORK, or BLOCK. If the verdict is not SHIP, the Reviewer lists exactly what needs to change and where.
Why the Reviewer cannot edit code: Anthropic's engineering team found that a model evaluating its own output (or having the ability to fix what it judges) produces biased reviews. The model prefers conclusions consistent with what it could just patch. A read-only Reviewer has no option but to be honest about what it sees. This structural constraint is what makes the review meaningful.

THE ORCHESTRATOR: ONE COMMAND RUNS ALL FOUR
This is the command that chains the four agents into a pipeline. You type one line and it runs Planner, Coder, Tester, Reviewer in order, each one waiting for the previous agent's handoff file before starting.
Create a file at .claude/commands/ship.md and paste this:
"Run the full feature pipeline for: $ARGUMENTS
Execute these stages in order. Do not skip ahead. After each stage, confirm the handoff file exists before starting the next.
Delegate to the planner subagent with the feature request above. Wait for .pipeline/spec.md.
If the spec has OPEN QUESTIONS, stop and show them to me. Otherwise delegate to the coder subagent. Wait for .pipeline/changes.md.
Delegate to the tester subagent. Wait for .pipeline/test-results.md. If tests failed, stop and show me the failures.
Delegate to the reviewer subagent. Show me .pipeline/review.md.
Report the final verdict. Do not merge anything. Leave the branch for my morning review."
How to use it: Open Claude Code and type:
/ship add rate limiting to the login endpoint
Or:
/ship build a user settings page with email notification preferences
Or:
/ship refactor the payment module to support multiple currencies
The orchestrator fires the Planner with your feature request. The Planner writes the spec. The Coder reads the spec and builds the feature. The Tester writes and runs tests. The Reviewer gives the final verdict. If anything goes wrong at any stage the pipeline stops and tells you exactly what happened.

THE COST MODEL
This pipeline is designed to be cost-efficient by using the right model for each role:
Planner on Opus: Runs once per feature. Highest quality reasoning for planning and architecture. Worth the premium because the spec quality determines everything downstream.
Coder on Sonnet: Produces the most tokens. Implementation against a clear spec does not need Opus-level reasoning. Sonnet at roughly 5x cheaper handles this perfectly.
Tester on Sonnet: Similar to the Coder. Writing and running tests against known changes is bounded work that Sonnet handles well.
Reviewer on Opus: Runs once per feature. Final quality gate. Catching a subtle issue here is worth the premium because missing it means a bug in production.
The result is that about 70% of the token spend goes to Sonnet (the cheap model) and only 30% goes to Opus (the expensive model). This is the same cost pattern Anthropic's own engineering team uses internally.

HOW TO USE IT OVERNIGHT
The real power of this pipeline is running it before you go to sleep and waking up to finished work.
Before bed: Create a new branch for the feature. Run /ship with your feature request. Close your laptop.
In the morning: Open the branch. Read .pipeline/review.md for the verdict. If it says SHIP, review the code yourself and merge. If it says NEEDS WORK, read the specific feedback and decide whether to fix it yourself or run the pipeline again with adjustments.
The pipeline does not merge anything automatically. It always leaves the branch for your review. You are the final human gate. The pipeline does the work. You make the decision.

TIPS FOR GETTING THE BEST RESULTS
Write clear feature requests. "Add rate limiting to the login endpoint, max 5 attempts per minute per IP, return 429 after limit" produces much better results than "add rate limiting somewhere." The more specific your request the tighter the Planner's spec.
Start with small features. Your first few runs should be bounded features like adding a new API endpoint, building a settings page, or refactoring a single module. Once you trust the pipeline on small features, scale up to larger ones.
Read the .pipeline files. Even when the verdict is SHIP, read spec.md, changes.md, test-results.md, and review.md. You will learn how each agent thinks and over time you will write better feature requests because you understand what the Planner needs.
Clean up .pipeline between runs. Before starting a new feature, delete the contents of .pipeline/ so the agents do not accidentally read stale files from the previous run. Or add a cleanup step to the beginning of your ship.md command.
Use git worktrees for parallel features. If you want to run multiple features through the pipeline at the same time, each one needs its own git worktree so the agents do not edit the same files. Claude Code supports a worktree flag on subagents for this exact use case.
