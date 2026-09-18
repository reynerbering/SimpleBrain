---
description: Run the four-agent feature pipeline (plan → code → test → review) on the current repo
argument-hint: <feature request>
---

Run the full feature pipeline for: $ARGUMENTS

If $ARGUMENTS is empty, stop and ask what to build. Do not infer a feature from the conversation.

## Preflight

1. Confirm the working directory is a git repo. If not, stop.
2. Check the current branch. If it is `main`, `master`, `develop`, or `trunk`, STOP and tell me — offer a branch name derived from the request (`<JIRA-KEY>-<slug>` if the request names a ticket, otherwise a bare kebab-case slug — **no `feat/` prefix**; confirm against the repo's own convention with `git ls-remote --heads origin`) and wait for my go-ahead. Never run the pipeline on a shared branch.
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

If the request names a Jira key, remind me to log the run in `tickets/<TEAM>/<KEY>.md` in the SimpleBrain vault — verdict, what the reviewer flagged, and any gate that tripped.
