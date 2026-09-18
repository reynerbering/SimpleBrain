---
type: design-doc
ticket: AS-8535
team: AS
status: building
repos:
  - clickapply
  - hosted-apply
  - cloud-lookup-api
grilled: 2026-09-16
updated: 2026-09-18
---

# AS-8535 — apply-flow

- **Status:** in progress — Phase 2 started, walking skeleton built (AS-9252)
- **Ticket:** [[AS-8535]] — *Job Application Re-Architecture - Phase 1*
- **Grilled:** 2026-09-16 via /grill-me
- **Last touched:** 2026-09-18

> ⚠️ **This doc supersedes the AS-8535 epic body.** The epic describes an AWS Step Functions
> re-architecture driven by fraud reduction, integrating a Business Rules Engine, Delivery Rules
> Engine and Event Hub, with SNS ingress and rollout by ATS partner and client tier. None of that is
> what was decided. Decision: leave the epic body alone, carry context in child tasks. Anyone reading
> the epic cold will build the wrong system — read this instead.

## Problem

The 15 Easy Apply job-board endpoints live in **`clickapply`** (not `hosted-apply`, as originally
assumed). They share a 13-stage spine, diverge at five forks, and have no abstraction between them —
no base class, no interface, no strategy map. The only dispatch table is `config/routes.js`, and
`SubmitEasyApply` exists on eight services with **eight different signatures**.

What is actually broken:

- **Nothing knows whether an application succeeded.** The response leaves at stage 07 and everything
  after runs as an unawaited promise. Twelve of fifteen boards are told `200 success` before the
  application exists. `CandidateServiceV2.createApplication` returns `undefined` and no caller awaits it.
- **Failures are invisible by construction.** CareerBuilder threw on every request from 2024-10-08 and
  still returned a 200 pixel — for nearly two years, with nobody alerted.
- **There is no state.** Not in `easyapplyapp`, not in `click`/`app`, not in hosted-apply's
  `Application`. The only durable record of a request is the archived raw body plus log lines.
- **The logs cannot be trusted.** `requestPath` leaks across requests via the pooled tedious
  connection — 56,505 mis-attributed lines in 7 days, one 1×1 pixel GET owning 666 lines spanning
  9h14m and 222 distinct applicants.
- **There are no tests.** `supertest` is a devDependency no test file imports. No test for
  `EasyApplyController`, any board service, `CandidateServiceV2`, or `ATSService`.
- **Onboarding a board costs 11 touchpoints across 8 files** plus a redeploy — except on the one
  config-driven route, where it costs a database row.

## Decisions

### Platform

- **.NET 10 on AWS Lambda durable functions**, `Amazon.Lambda.DurableExecution` 2.0.0 (GA) — because
  the SDK ships a real in-process orchestration runner (`DurableTestRunner`) whose tests run unchanged
  against a deployed function (`CloudDurableTestRunner`). The testability requirement is met by the
  platform rather than by us.
- **One repo, Lambda Annotations model** — attribute-driven, source-generated, hides the service envelope.
- **Terraform pinned `~> 6.25`**, own module per repo, no SAM template — Terraform is the AS team
  standard (8 of 9 AS Lambdas) and `durable_config` needs provider ≥ 6.25.0. 7 of those repos currently
  pin `~> 5.0`, which cannot express it at all.
- **`us-east-1`, Apply Systems account, QA / UAT / PROD.** Region availability confirmed.
- **Walking skeleton first** — one durable function, one injected service, one local test, one cloud
  test — because `[DurableExecution]` combined with `[FromServices]` is demonstrated in no AWS doc or
  sample. Confirm the DI model before any real code exists.

### Four layers, four durable functions

Chained `ctx.InvokeAsync`. Separate functions, not child contexts — *"we must uncouple these things to
add more flexibility and retry mechanisms."*

| Layer          | Operations                                                                                          | Terminal state                   |
| -------------- | --------------------------------------------------------------------------------------------------- | -------------------------------- |
| **1 Validate** | Archive · Authenticate · Dedupe · CheckRequired                                                     | `Validated` / `Rejected(reason)` |
| **2 Parse**    | ExtractJobRef · ResolveJob · ExtractApplicant · AcquireResume · TransformAnswers · ResolveQuestions | `Parsed` / `Diverted`            |
| **3 Assemble** | CreateCandidate · AttachResume · SubmitApplication · RecordApplication                              | `Assembled`                      |
| **4 Delivery** | BuildDeliveryPayload · Deliver → EAC · Postback                                                     | `Delivered`                      |
|                |                                                                                                     |                                  |

- **The cut is on transaction boundaries.** Assemble writes only to systems JobTarget owns; Delivery
  writes only to systems it does not. Different failure modes, different retry appetite, different blast
  radius. `jt_application_id` is the handoff token between them.
- **`Diverted` is a success state**, not a failure — the job had required screener questions the board
  did not collect, so the candidate is emailed a link. The return leg starts a **fresh execution**
  sourced as hosted apply; no `WaitForCallback`, because the questions are not answered in-session.
- **Carry `origin_board` separately from `source`.** Today the return leg drops the board name entirely
  (`send-application.js` never forwards the `source` it stores), which is why postback cannot fire on a
  diverted application and why the two halves cannot be rejoined.

### Validate observes; it does not reject

- **All three verdicts computed, none enforced on day one.** A faithful enforcing Validate would start
  rejecting traffic that sails through on **twelve of fifteen boards** today — LinkedIn alone has
  **20.9% of prod applies (2,692) failing all four HMAC digests and being processed anyway**, most
  likely because `:1709` re-serialises the body instead of hashing the raw signed bytes. That is our
  bug, not theirs.
- **Dedupe ships silent** — implemented, evaluated, acting on nothing, flippable later.
- **Verdicts live beside the state, not in it.** State stays `Validated`; a `verdicts[]` carries
  `{check, outcome, wouldHaveRejected}`. That is what makes enforcement safe to turn on later — a
  queryable record of how often each check *would* have fired, per board.
- **Archive to S3 before any verdict.** Today the archive is stage 04, after auth and dedupe, so
  rejected traffic is never recorded. The day enforcement flips on, that would blind us to exactly the
  traffic we just started dropping.
- **The S3 key is the handoff token** between all four functions. Never pass the body — eleven boards
  send inline base64 résumés and the per-execution state ceiling is 100 MB.
- **`client_secret` is not carried over.** `HitService.js:190-191` persists it to Mongo in cleartext today.

### Abstraction — config first, code only where needed

- **`BoardAdapterBase` specified from the AJV contract** in `EasyApplyValidationService.js`, *not*
  copied from the generic v2 code. The contract is a written specification, deliberately decoupled from
  the live path; the v2 code carries 15 must-fix defects (catalogued below) that would otherwise become
  every board's defects.
- **`GenericV2Adapter` is a sibling, not the ancestor** — *"V2 generic is the new integrations coming in,
  but the other jobboards should have a base model."* It overrides `Authenticate` only.
- **Config overrides before code overrides.** Most boards differ only in *where a field is*. Code
  adapters exist only where config cannot express the behaviour: Seek (outbound OAuth fetch), Seek and
  Snagajob (rendered PDF), LinkedIn (three credential tiers).
- **Two adapter families, because the variance runs on two axes.** `IBoardAdapter` owns
  Validate / Transform / Postback (board-shaped). `IDeliveryAdapter` owns Build / Deliver (ATS-shaped).
  Assemble is shared and has no adapter. Forcing both onto one interface would push an ATS switch
  *inside* each board implementation — the exact copy-paste being migrated away from.
- **easy-apply-connector is the delivery boundary.** Everything goes through it, so `IDeliveryAdapter`
  has one implementation today. See the open question on EAC readiness.

### Cross-cutting

- **`StageRunner` decorator around pure stages.** No operation touches `IDurableContext`. This is both
  AWS's recommendation and what makes DI trivial — the context never needs mocking.
- **Per-stage error classification**, each its own taxonomy, extensible.
- **Every layer logs its state**, success or failure, with an explicit reason.
- **Correlation travels in the event, never ambiently.** Evidence-backed, not preference: clickapply's
  ambient `AsyncLocalStorage` context is carried across requests by the single-slot tedious connection
  pool, and it invalidated every dashboard sliced by `requestPath`.

### State and observability

- **DynamoDB state index, 1-year retention, idempotent upserts keyed on execution id.**
- **EventBridge transitions** to the existing buses.
- **CloudWatch-readable canonical event per operation** — layer, operation, outcome, reason,
  classification, board, mode, attempt, duration, plus correlation. **Reasons are codes, never applicant
  data** (`ResumeFetchUnauthorized`, not the résumé).
- **Hybrid write policy: the state transition is inside the step; metrics and emits are best-effort. The
  application wins** — a telemetry failure never fails an application.
- **Operator re-drive reads the Dynamo index**, falls back to the S3 archive, keyed on `applicantGuid`.
  The S3 object is written first and is therefore the most reliable record in the system.
- **The durable journal caps at 90 days** (`RetentionPeriodInDays` 1–90). From month 4 to month 12 the
  Dynamo item is all there is, so it must carry the per-layer outcomes and reasons, not just current state.

### Retry and recovery

- **Pure operations `None`** — retrying a pure function is theatre.
- **Core-facing calls `Transient`**, because *"Core never goes down because I maintain it."*
- **`AcquireResume` stays `Default`** — LinkedIn and Seek fetch over *their* APIs, which that assurance
  does not cover.
- **Five irreversible operations get `StepSemantics.AtMostOncePerRetry`**: `CreateCandidate`,
  `AttachResume`, `SubmitApplication`, `Deliver`, `Postback`.
- **Forward recovery, not compensation.** AWS ships no compensation primitive and there is no saga page
  in the durable-execution docs. Four of the seven delivery-chain calls have no possible undo — you
  cannot un-create a Core jobseeker or un-POST to iCIMS. So: catch `StepInterruptedException`, query
  downstream, resume. **Probes are built for four operations.**
- **`Postback` has no probe and prefers double-send.** Boards will occasionally receive the same
  notification twice and their counts will run slightly high. Under-reporting an application is worse for
  the board relationship than a small over-count.
- **Timeouts: Validate 1 min · Parse 5 min · Assemble 5 min · Delivery 24 h.** `ExecutionTimeout` is
  **create-time only** — changing it forces a function replacement, which kills in-flight executions.
- **Past the deadline: terminal `Failed` with a reason, in the index, re-drivable.** A Core outage
  becomes a re-drive queue instead of silent loss.

### Repo coding standards

- **Never `catch (StepException)` bare** — `StepInterruptedException` derives from it, so a bare catch
  swallows the suspend signal and corrupts the execution. Filter it and `NonDeterministicExecutionException`.
- **Retries live inside each function, never at the call site.** `InvokeConfig` takes no retry strategy
  and analyzer rule DE002 forbids wrapping `InvokeAsync` in a step — despite AWS's own retry docs showing
  exactly that.
- **Promote DE001 / DE002 / DE003 to `error`.** All four analyzers ship as Warning/Info; they describe
  real correctness bugs that compile clean by default.
- **Qualified ARNs are mandatory** (`publish = true` + alias) and IAM `Resource` must be
  `function:<name>:*`, or durable execution ARNs never match and it fails as a silent deny.

### Streamlining decisions

- **Résumé to S3, never local disk.** Today every board writes to `.tmp/` with a filename of
  `"{fullName} ({jobId}).{ext}"` — no guid, flat directory, so two same-named applicants to the same job
  overwrite each other. On Lambda `.tmp` is per-container anyway. This deletes the collision and the leak
  class together.
- **Cleanup is a `finally`, not an operation.** `removeResumeTmp` is step 6 of 7 today, which is why every
  ATS delivery failure leaks a file.
- **Each operation declares its own retry and semantics** rather than inheriting a global policy.

### Migration

- **clickapply keeps the URLs and forwards** — the only option requiring zero board-side change, with a
  flag as free rollback. The shim points per-environment so QA clickapply feeds QA apply-flow.
- **apply-flow owns a new S3 raw-body archive**, written first in Validate.
- **Replay + shadow as the cutover gate**, canary held in reserve. Replay first because it is free and
  safe and catches the dominant failure class; the atlas overturned seven boards' documented payload
  shape, so field-path drift is the expected bug.
- **Structure-only capture in prod** — field paths, types, a fingerprint of the assembled application. No
  names, emails, phones, résumé bytes or free text. Same discipline as the atlas capture that ran against
  6.1M prod bodies.
- **Per-board cutover. ZipRecruiter first** — no auth gate to reason about, high volume, seven payload
  shapes, and the closest thing to a reference implementation of the spine.
- **Fixes land in apply-flow only, with an expected-diff list.** Ten of the fifteen Class-A defects change
  behaviour for boards that work today, so replay will show intentional diffs. The list doubles as the
  changelog.
- **Exception: A2 (cover letter) is fixed in clickapply now** — one character, silently losing real
  applicant data on every board.

## Rejected

- **Step Functions** — rejected in favour of durable functions. AWS's own guidance: primarily-Lambda work
  belongs in durable functions; multi-service orchestration belongs in Step Functions. This is
  Lambda-centric, and plain C# with real unit-test frameworks matters more here than a visual designer.
  *(Note: the AS-8535 epic body still specifies Step Functions.)*
- **Cutting the stages by observability** (Intake 01–07 / Background 08–13) — rejected because it bakes in
  the fire-and-forget fork that is the service's central flaw.
- **`WaitForCallback` for the Hosted Apply divert** — rejected: questions are not answered in-session, so
  suspending an execution on them is wrong. It would also carry two copies of the callback payload and one
  open execution per outstanding handoff, on every board.
- **A single `IBoardAdapter` owning the whole chain** — rejected because the outbound half is ATS-shaped,
  not board-shaped, and a single board's traffic fans across every ATS its employers use.
- **Fully config-driven with no code adapters** — rejected because no config DSL can express Seek's
  outbound OAuth fetch or Snagajob's rendered PDF without becoming a programming language.
- **Fifteen bespoke adapters** — rejected because most boards differ only in field paths.
- **`BoardAdapterBase` modelled on the generic v2 behaviour** — rejected after audit. All 15 boards would
  inherit the multiselect defect, the unguarded `applicant` dereference and the swallowed lookup failures.
- **New API Gateway / Lambda Function URLs as ingress** — rejected as a *first* step. All 15 boards would
  have to repoint, and Indeed and LinkedIn realistically cannot.
- **Child context (`RunInChildContextAsync`) for the Assemble → Delivery seam** — rejected: decoupling in
  code only, with Delivery's lifetime still welded to Assemble's.
- **EventBridge/SQS between Assemble and Delivery** — rejected: independence at the cost of the linked
  journal, rebuilding correlation by hand.
- **CloudWatch Logs alone as the state store** — rejected on evidence. Log-derived state for this flow has
  a track record: five separate investigations independently hit the `requestPath` leak.
- **Telemetry writes that can fail an application** — rejected. The application wins.
- **Reproducing the 15 Class-A defects faithfully** — rejected; we would knowingly ship them.
- **Fixing the defects in clickapply first** — rejected; it is work in the repo being retired.
- **Migrating CareerBuilder and Facebook** — rejected. CareerBuilder has produced zero applications since
  2024-10-08 and `atsRequisitionId` is an empty string in all four prod documents that exist; it is a
  rewrite if the business still wants it. Facebook has zero hits across 35 days of prod logs, the span
  pipeline, QA and UAT, and could not work if called.
- **`jobtarget` as a board** — rejected after verification. It is a first-party ingress with three
  producers (widget ~99.8%, Apply Agent, Hosted Apply return leg ~0.2%), modelled as modes.
- **`Diverted` renamed to something more positive** — `HandedOff` was proposed and considered; `Diverted`
  kept by decision.

## Scope

**In**

- 11 named boards: Indeed, Monster, ZipRecruiter, Nexxt, Talent.com, Snagajob, JobGet, Seek, JobCase,
  GetWork, LinkedIn
- The `jobtarget` first-party ingress, modes `widget` · `applyAgent` · `hostedapply`
- The `GenericV2` on-ramp for new partner integrations
- Four durable functions, 17 operations, DynamoDB state index, S3 archive, EventBridge transitions
- Replay + shadow harness and the expected-diff list
- The clickapply forwarding shim and its per-board flag

**Out**

- **CareerBuilder** and **Facebook** — not migrated
- Per-ATS delivery fan-out — everything goes through easy-apply-connector
- CBS-2097 (ATS migration to EAC) — explicitly ignored by decision
- The Business Rules Engine, Delivery Rules Engine, Event Hub and fraud-scoring work named in the AS-8535
  epic body — not part of this design
- ZipRecruiter's unread `profile` object (job history, education, certifications, present on 100% of
  bodies, read by no code path)
- Rotating the plaintext credentials in `cloud-lookup-api` — real, but separate work

## Class A defects — must not become base-class defaults

Audited against `clickapply @ develop` (c2fc5a98). ✅ = produces an intentional replay diff.

| # | Defect | ✅ |
| --- | --- | --- |
| A1 | `AdditionalQuestionsTranslateService.js:3526` — push onto uninitialised `formatted.values` for a scalar multiselect answer. `SITETOJT` returns `undefined`; **every answer is lost**, divert cannot fire, board still gets 200. Only `case "generic"` omits the init that `nexxt` (`:2976`) and `getwork` have. **jooble crashes on 43% of its requests.** | ✅ |
| A2 | Contract says `coverLetter`; both submit paths read `coverletter`. Always `null`. `sendToHostedApply:230` hardcodes `coverLetter: null` too — broken twice, independently. | ✅ |
| A3 | `EasyApplyService.js:152-176` — Core posting lookup failure caught without `return`. `job` stays `undefined`, `HitService.parse` throws, outer catch swallows, **200 returned and no archived body**. Unrecoverable. | ✅ |
| A4 | `:169-172` — `getJobDataByPostingId` returns `null`; caller calls `.length` on it. 200, nothing persisted, intended `res.badRequest()` never fires. | ✅ |
| A5 | `:152` — `/^[0-9]*$/` matches the empty string (`*` should be `+`). | ✅ |
| A6 | `:144-147` — `req_aux = req` is an alias; partner-supplied `analytics.userAgent` permanently overwrites the real header. The genuine transport UA is unrecoverable. Affects every board. | — |
| A7 | `recruiterIdCheck` has two await semantics by flag; on the detached arm `res.status(400)` fires after the 200 shipped → `ERR_HTTP_HEADERS_SENT`. | ✅ |
| A8 | **No `unhandledRejection` handler anywhere in the repo**, and Node ≥15 defaults to throw. A7's throw is a process-killer. | ✅ |
| A9 | `:216-218` — `req.body.applicant` dereferenced two lines before the optional-chained guard; also overwrites `fullName` with `"undefined undefined"`, which becomes the temp filename. | ✅ |
| A10 | `recruiterIdCheck` injects a **divisionId** into `job[3]` → `recruiter_id` for ATS and connection calls. The two arms return different shapes, so the fix is silently inert on the core-v2 arm. | ✅ |
| A11 | Résumé temp-file leaks: divert path never calls `removeResumeTmp`; ATS-failure path skips it via the catch at `CandidateServiceV2.js:198`. | — |
| A12 | Undeclared globals — `LookupService.js:116` `job = [...]` leaks to `globalThis`, read back in `case 'nexxt'`. **Cross-request data leak between concurrent applications.** | — |
| A13 | `postbackToSite`'s first `await` sits outside its own `try`; called fire-and-forget with no `.catch()`. | — |
| A14 | `EasyApplyController.js:1368-1375` — 200 is unconditional, and the `catch` writes **no response at all**, leaving the socket open until timeout. | ✅ |
| A15 | `flattenAnswersEnabledBoards` split without trimming and captured at module load — `"indeed, jobcase"` yields `" jobcase"`, which never matches. | ✅ |

## Facts verified during Phase 1

- **`media_id` is a string** — `cloud-lookup-api`'s `Lookupdb` is schemaless Mongo and both writers store
  strings (`POST /lookup` rejects non-strings with a 400). `=== 29462` at `EasyApplyController.js:1687`
  can never match. Scoped to the hashed-postingId branch; numeric ids route via MSSQL where
  `dbo.jobs_sites.site_id` is a real `int`. **Killed in the new design by coercing the quad once in
  `ResolveJob`.**
- **Stale `requestPath` is real** — log group `/ecs/prod-click2apply-app`. One pixel GET owns 666 lines
  over 9h14m, 222 distinct `applicantGuid`, one `trace_id`. 56,505 mis-attributed lines in 7 days, a
  floor. Mechanism is the single-slot tedious pool, not `await`.
- **"Strip frees zero bytes" is false** — `ATSService.js:18-22` frees roughly a full copy of the base64
  résumé. The real no-op strip is `EmitterService.js:120-122`, which re-hangs the file-bearing subtree
  under a new key before deleting it.

## Open questions

- OPEN QUESTION: **Is easy-apply-connector actually ready to be the sole delivery target?** AS-8535 lists
  ATS migration to EAC as out of scope and tracked under **CBS-2097, a prerequisite blocker**. Decision
  was to ignore CBS-2097. If EAC is not in front of every ATS, `IDeliveryAdapter` needs the per-ATS
  fan-out this design removed.
- OPEN QUESTION: **What is in the `easyapplysite` collection?** Unreachable — the MongoDB Atlas MCP is
  unauthenticated and no other connector reaches Mongo. Which boards are registered on
  `/v2/easyapply/:board`, and how many, is unknown. This scopes the eventual v2 migration.
- OPEN QUESTION: **Is LinkedIn skipping the `hasRequiredQuestions` guard deliberate or a bug?**
  `ResolveQuestions` is shared, so unifying it either fixes LinkedIn or breaks an intended exception.
- OPEN QUESTION: **Is the `'hostedapply'` re-translation lossy for any board?** Answers normalised at
  divert time under `SITETOJT(body,'<board>')` are re-translated as `'hostedapply'` on the return leg.
  Requires reading the 3,903-line translator per board.
- OPEN QUESTION: **Does `apply-flow` get a row in the README repo inventory?** It is not there, so it is
  deliberately absent from this doc's `repos:` property rather than invented.
- OPEN QUESTION: **`easy-apply-connector` is not an AS repo** but is the delivery boundary. Ownership for
  changes needed there is unresolved.
- OPEN QUESTION: **What are the production values** of `dedupeFeature`, `candidateServiceV2`,
  `core_v2_migrate_feature_flag`, `flattenAnswersEnabledBoards`? `.env*` and `config/local.js` are
  gitignored with no example file. Every "this flag is unset in prod" claim comes from an audit, not
  source — and they decide what is safe to delete.
- OPEN QUESTION: **Is `DUPLICATE_THRESHOLD = 50` meaningful?** Inherited with the dedupe key
  (`app:{board}:{postingId}:{email}`, 24h); its semantics were never pinned down.

---
## 2026-09-18 — post-implementation revision (AS-9252, walking skeleton)

Phase 2 started. The skeleton is built, on branch `feat/AS-9252-walking-skeleton` in a new local repo
at `C:\JT Repositories\apply-flow` (commit `6d4c23e`, 51 files). No remote yet.

**Changed**

- **The DI gate is answered, and the fallback is not needed.** `[DurableExecution]` composes with
  Lambda Annotations DI — but **only through the constructor**. `[FromServices]` method parameters are
  rejected outright: `AWSLambda0142 — must have the signature (TInput, IDurableContext)`. Exactly two
  parameters, and no `ILambdaContext` either. So the class-library model with a hand-built container is
  **off the table**, and AS-9253 / AS-9254 keep their planned shape.
- **`Amazon.Lambda.Annotations` must be 2.x.** `DurableExecutionAttribute` does not exist in 1.x. The
  version cached on this machine was 1.7.0, which has no durable support at all — the design said
  "Lambda Annotations model" without a version, and 1.x would have looked like the model simply not
  working. Pinned to 2.4.0.
- **`[DurableExecution]`'s constructor argument is `ExecutionTimeout` in seconds**, with
  `RetentionPeriodInDays` as a property. The per-layer deadlines decided in Phase 1 are therefore
  expressed in code, not only in infra: 60 / 300 / 300 / 86400, retention 90 on all four. Verified
  against the generated `serverless.template` for each function.
- **`ANNOTATIONS_HANDLER` is a required environment variable**, and the Lambda handler is the bare
  assembly name. Neither is guessable — both were read off the generator's emitted template. Terraform
  sets them; getting either wrong yields a function that deploys and never dispatches.
- **The generated `serverless.template` is committed on purpose.** The repo deploys with Terraform, not
  SAM, so the template is dead weight as infra — but it is the only mechanical cross-check that a
  changed `[LambdaFunction]` attribute has diverged from `infra/lambda.tf`.
- **Verdicts are keyed on a known-board list, not on a non-empty check.** First cut checked only that
  the board was non-blank, which cannot fail without also breaking the archive key — and Archive runs
  *before* any verdict by decision, so the check was unreachable in practice. Replaced with a
  known-board set (configurable, defaulting to the eleven in-scope boards plus `jobtarget`). CareerBuilder
  is absent by design, which gives the "would have rejected" path a real case to exercise.
  ⚠️ **The board slugs in `KnownBoards.InScope` are provisional** — the design doc names the boards in
  prose only. Canonical on-the-wire slugs get pinned by AS-9254; the list is overridable by
  configuration so the guess is not load-bearing.

**Confirmed, not changed**

- **Terraform provider floor.** The design said `~> 6.25`; the devops catalog is on `>= 6.28, < 7.0`,
  which is compatible and stricter. Using the catalog's.
- **`publish = true` + alias, and IAM `Resource = function:<name>:*`** are both in `infra/`, as decided.
- **Four function projects, shared pure core, no operation touching `IDurableContext`.** Holds.

**What is not done**

- **`infra/` has never been validated.** Terraform is not installed on this machine, so nothing has been
  through `init`, `validate`, `fmt` or `plan`. It is written, not proven.
- **The cloud test has never run.** `CloudDurableTestRunner` is wired and reports *skipped* (never
  passed) unless `APPLY_FLOW_VALIDATE_FUNCTION` is set. apply-flow has not been deployed, so AS-9252's
  "Done when" is **not** met yet.
- **CI builds and tests but does not deploy** — see the new open question below.
- **OTel is off.** The catalog defaults it on, but its pinned ADOT ARNs are the Python and Node distros.
  The .NET layer ARN was not guessed.

**New open questions**

- OPEN QUESTION: **There is no `terraform-dotnet` CI/CD component, and no .NET leaf in the devops
  catalog.** `jobtarget/devops/templates/lambda` is the live standard — components under
  `templates/<name>/`, leaves under `catalog/<iac>/<runtime>/<pattern>/` — but the only stable leaf is
  `terraform/python/sns-sqs-lambda` and the only component is `terraform-python`.
  `catalog/terraform/dotnet/` is an empty `.gitkeep` and every .NET cell in the matrix is 🟡 planned.
  apply-flow's conventions were hand-ported, which means the env/tag deployment model, OIDC role
  assumption and `TF_HTTP_*` state wiring the component owns are **not** wired. Either devops adds a
  `terraform-dotnet` component, or apply-flow forks the standard on its first .NET consumer.
- OPEN QUESTION: **Is `owner = "apply-systems"` an accepted tag value?** The catalog warns that the JT
  compliance scanner rejects placeholder `product`/`owner` values. `product = "applysystems"` is listed
  as a valid slug in the catalog; `owner` was taken from the `team = "apply-systems"` tag the existing
  AS Lambda repos set, and has **not** been checked against the scanner's allowed list.
- OPEN QUESTION: **Does apply-flow get a row in the README repo inventory, and a GitLab project?**
  Still no row (carried over from Phase 1), and now also no remote — the repo is local-only by decision.
  Expected namespace by convention is `jobtarget/apps/apply-systems/apply-flow`, not verified.

**Reviewer flagged**

- Pipeline not run. AS-9252 was built directly by decision — the gate was exploratory and its answer
  could have been "this does not work", which is not a shape `/ship` handles well.
