// Four-Agent Feature Pipeline — Workflow-script variant.
//
// Adapted from "How to Build a 4-Agent Dev Team That Ships Features While You Sleep":
// https://docs.google.com/document/d/1lunO8LyDEnq8T6mBvFKpQIsJ7oskFWXxX3wo6eqNPDs
// The four agent prompts are the doc's. This script is NOT from the doc — it is a
// local adaptation that moves the orchestration from a prose slash-command into
// deterministic control flow. See coding/four-agent-pipeline.md.
//
// INSTALL: copy to ~/.claude/workflows/ship.js for a global install, or into a
// single repo at <repo>/.claude/workflows/ship.js.
// Requires the ship-* agents at ~/.claude/agents/ — agentType resolves against
// them, so each stage inherits its pinned model and tools.
//
// RUN:  Workflow({ scriptPath: "<path>/ship.js",
//                  args: "add rate limiting to the login endpoint, max 5/min per IP, 429 after limit" })
//
// NOTE: the /ship slash command is the primary entry point. This script is the
// alternative for when you want the gates enforced as code rather than as
// instructions. Both drive the same four ship-* agents.
//
// WHY A SCRIPT INSTEAD OF /ship: the gates become real control flow instead of
// instructions a model may skip under pressure. OPEN QUESTIONS and failing tests
// hard-stop here — an orchestrating model cannot decide to push through them.
// This pipeline is strictly sequential by design; there is no parallelism to gain.

export const meta = {
  name: 'ship',
  description: 'Four-agent feature pipeline: plan, code, test, review. Stops at every gate, never merges.',
  whenToUse: 'Running a bounded feature or refactor end-to-end on a branch, with spec/test/review gates.',
  phases: [
    { title: 'Plan', detail: 'Planner (Opus) writes .pipeline/spec.md', model: 'opus' },
    { title: 'Build', detail: 'Coder (Sonnet) implements the spec', model: 'sonnet' },
    { title: 'Test', detail: 'Tester (Sonnet) writes and runs tests', model: 'sonnet' },
    { title: 'Review', detail: 'Reviewer (Opus), read-only, gives the verdict', model: 'opus' },
  ],
}

const SPEC_SCHEMA = {
  type: 'object',
  required: ['openQuestions', 'filesPlanned', 'summary'],
  properties: {
    openQuestions: {
      type: 'array',
      items: { type: 'string' },
      description: 'Ambiguities that must be resolved by a human. Empty array if the spec is unambiguous.',
    },
    filesPlanned: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string', description: 'Two or three sentences on the planned approach.' },
  },
}

const CHANGES_SCHEMA = {
  type: 'object',
  required: ['filesChanged', 'summary', 'testFocus'],
  properties: {
    filesChanged: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    testFocus: { type: 'array', items: { type: 'string' } },
    blockedOnOpenQuestions: { type: 'boolean' },
  },
}

const TEST_SCHEMA = {
  type: 'object',
  required: ['allPassed', 'testFiles', 'failures'],
  properties: {
    allPassed: { type: 'boolean' },
    testFiles: { type: 'array', items: { type: 'string' } },
    failures: {
      type: 'array',
      items: {
        type: 'object',
        required: ['test', 'reason'],
        properties: { test: { type: 'string' }, reason: { type: 'string' } },
      },
    },
    runnerCommand: { type: 'string', description: 'The exact command used to run the suite.' },
  },
}

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['verdict', 'items'],
  properties: {
    verdict: { type: 'string', enum: ['SHIP', 'NEEDS WORK', 'BLOCK'] },
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['what', 'where'],
        properties: {
          what: { type: 'string' },
          where: { type: 'string' },
          severity: { type: 'string', enum: ['minor', 'major', 'critical'] },
        },
      },
    },
    rationale: { type: 'string' },
  },
}

const request = typeof args === 'string' ? args.trim() : ''
if (!request) {
  return { stoppedAt: 'input', reason: 'No feature request passed. Provide it via the args input.' }
}

// ---- Stage 1: Plan -------------------------------------------------------
phase('Plan')
const spec = await agent(
  `Feature request: ${request}

Follow your agent definition exactly. Write the spec to .pipeline/spec.md.

Before you start, ignore and overwrite any pre-existing .pipeline/spec.md — it is stale output from a previous run.

Then return the structured summary. openQuestions must list every ambiguity you flagged as an OPEN QUESTION in the spec, verbatim. If the request is fully unambiguous, return an empty array — do not invent questions to seem thorough, and do not suppress real ones to keep the pipeline moving.`,
  { agentType: 'ship-planner', phase: 'Plan', label: 'plan' }
)

if (!spec) return { stoppedAt: 'Plan', reason: 'Planner did not return a result.' }

if (spec.openQuestions.length > 0) {
  log(`STOP — planner raised ${spec.openQuestions.length} open question(s).`)
  return {
    stoppedAt: 'Plan',
    reason: 'Spec contains OPEN QUESTIONS. Resolve them, then re-run.',
    openQuestions: spec.openQuestions,
    spec: spec.summary,
  }
}

log(`Spec covers ${spec.filesPlanned.length} file(s). No open questions.`)

// ---- Stage 2: Build ------------------------------------------------------
phase('Build')
const changes = await agent(
  `Implement the spec at .pipeline/spec.md. Follow your agent definition exactly.

Write your summary to .pipeline/changes.md, then return the structured result.

If you find OPEN QUESTIONS in the spec, do not guess: set blockedOnOpenQuestions true, write nothing, and return immediately.`,
  { agentType: 'ship-coder', phase: 'Build', label: 'build' }
)

if (!changes) return { stoppedAt: 'Build', reason: 'Coder did not return a result.', spec: spec.summary }

if (changes.blockedOnOpenQuestions) {
  log('STOP — coder found open questions the planner did not surface.')
  return { stoppedAt: 'Build', reason: 'Coder hit OPEN QUESTIONS in the spec.', spec: spec.summary }
}

log(`Coder touched ${changes.filesChanged.length} file(s).`)

// ---- Stage 3: Test -------------------------------------------------------
phase('Test')
const tests = await agent(
  `Test the changes described in .pipeline/changes.md. Follow your agent definition exactly.

Write results to .pipeline/test-results.md, then return the structured result.

Report honestly. If the suite fails, set allPassed false and list the failures — do NOT fix the code, and do not weaken or skip a test to make it pass. A red suite is a valid, useful outcome here.

If you cannot determine how to run the repo's test suite, treat that as a failure with reason "no test runner identified" rather than guessing a command.`,
  { agentType: 'ship-tester', phase: 'Test', label: 'test' }
)

if (!tests) return { stoppedAt: 'Test', reason: 'Tester did not return a result.', changes: changes.summary }

if (!tests.allPassed) {
  log(`STOP — ${tests.failures.length} failing test(s).`)
  return {
    stoppedAt: 'Test',
    reason: 'Tests failed. Pipeline halted before review, per the stop-on-red rule.',
    failures: tests.failures,
    changes: changes.summary,
  }
}

log(`All tests green across ${tests.testFiles.length} test file(s).`)

// ---- Stage 4: Review -----------------------------------------------------
phase('Review')
const review = await agent(
  `Review the full pipeline output. Follow your agent definition exactly.

You are READ-ONLY. Do not edit, stage, commit, or merge anything.

Read .pipeline/spec.md, .pipeline/changes.md, .pipeline/test-results.md, and run git diff.

Write your verdict to .pipeline/review.md, then return the structured result.

The tests are green. That is not evidence the code is correct — it is only evidence the tests pass. Judge the diff against the spec on its own merits. If the code is wrong, say BLOCK regardless of the green suite.`,
  { agentType: 'ship-reviewer', phase: 'Review', label: 'review' }
)

if (!review) return { stoppedAt: 'Review', reason: 'Reviewer did not return a result.', changes: changes.summary }

log(`VERDICT: ${review.verdict}`)

// Nothing is merged, ever. The human is the final gate.
return {
  verdict: review.verdict,
  request,
  spec: spec.summary,
  filesChanged: changes.filesChanged,
  testFiles: tests.testFiles,
  runnerCommand: tests.runnerCommand,
  reviewItems: review.items,
  rationale: review.rationale,
  handoffFiles: [
    '.pipeline/spec.md',
    '.pipeline/changes.md',
    '.pipeline/test-results.md',
    '.pipeline/review.md',
  ],
  nextStep: 'Read .pipeline/review.md, then the diff. Merge is a human decision.',
}
