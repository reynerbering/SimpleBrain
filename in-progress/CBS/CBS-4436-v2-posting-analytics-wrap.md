---
type: design-doc
ticket: CBS-4436
team: CBS
status: decided
repos:
  - CoreAPI
grilled: 2026-09-17
updated: 2026-09-18
---

# CBS-4436 — V2 posting analytics wrap

- **Status:** **decided 2026-09-18. Phase 1 is complete and Phase 2 is unblocked.** Q1–Q9 answered,
  GATE 1 passed 20/20 in UAT, GATE 2 cleared, Q3 = seam (i), Q4 = non-fatal. **No `OPEN QUESTION`
  markers remain.** The Planner rider is in the Q3 and Q4 entries: re-throw on a dead transaction.
- **Ticket:** [[CBS-4436]] — *Discovery: analytics click-to-apply hash missing for postings created via core-api V2 create path — decide whether to add inline wrap*
- **Jira:** CBS-4436 · Investigation · High · Selected for Development · reporter Shervin Ivari · assignee me
- **Grilled:** 2026-09-17 via /grilling — **complete**
- **Last touched:** 2026-09-18

> **Both gates cleared 2026-09-18.** GATE 2 — sprocs re-read live on prod/uat/qa, cache faithful, doom
> question answered in seam (i)'s favour. GATE 1 — answered from prod DB state instead of the
> flip-test, which the cohort's remediation had made impossible; **the root cause holds**. The
> "Verified facts" and "Sproc facts" sections are done and do not need redoing — read out of the repo
> at `fcf24ca5` and now live from the database, not guessed.

## Problem

The analytics / click-to-apply URL (`job_employanalytics.tracking_url`, surfaced as `clickToApplyUrl`
in V2 and `application_method_analytics_url` in V1) is **null for a small set of live postings**,
because the `job_employanalytics` hash row was never created.

Per the ticket's root cause (confirmed by the reporter via prod CloudWatch + code + DB):

- The **V2 create path** `POST /api/v2/posting` never writes the hash. The inline wrap exists only in
  legacy V1 `JobService` and was never ported.
- V2-created postings depend entirely on after-the-fact backstops: the Marketplace UI
  (`/internal/analytics/FixUrlNotWrapped`), the PostMaster sweep
  (`PM.usp_get_jobs_applyurl_not_wrapped`, gated on `INNER JOIN PM.campaign_posting` +
  `status_id IN (2,4)` + created 12h–1mo ago), and ats-api's own wrap thread.
- A posting that misses **all** backstops stays unwrapped permanently. No error, no retry.

Affected slice is the intersection that misses every backstop: non-campaign partner-api direct
orders, organic/OFCCP fan-out with no `campaign_posting` row, and a few pgm postings outside the
sweep window. 13 posted + 22 spider postings confirmed in prod for 2026-07 — IDs are in the Jira
ticket, not duplicated here.

## Verified facts

Read out of `C:\JT Repositories\CoreAPI` on 2026-09-17, branch
`CBS-4643-ofccp-getjobs-param-validation`, HEAD `fcf24ca5`. Not guessed, not taken from the ticket.

**How V1 does it**

- `CoreAPI.Endpoints.V1/Core/Services/JobService.cs:415` (and again at `:834`) calls
  `_analyticsService.CreateWrappedUrlsForPostingAsync(postingId)` **after** the posting write
  succeeds (`obj.status == 0`), inside a `try/catch` that logs and swallows. Non-fatal by design —
  the comment says so explicitly: *"the posting is already created."*
- `CreateWrappedUrlsForPostingAsync` → `GetWrappedUrlTargetsAsync(postingId)` → one
  `usp_CreateWrappedUrl` call per target.
- `GetWrappedUrlTargetsAsync` is a hand-tuned UNION: the posting itself (clustered seek on
  `jobs_sites.id`) plus its media-package children (`jobs_features.feature = 'from_media_package'`,
  `value1 = @postingId`). The comment warns the `OR` form defeats the seek and scans a 174M-row
  table — **do not "simplify" it.**
- Hash = `HashIdsWrapper.GenerateHash(_hashIdSalt, [jobId, postingId, siteId, recruiterId])`.
  `imgUrl` = `click2apply.net/v/<hash>`. The sproc owns apply-url / masking / tracking resolution
  and idempotency.
- Note V1 `AnalyticsService` still carries the **older** `RunJobAsync` path too, which does a raw
  `INSERT INTO dbo.job_employanalytics` gated on `is_pending_tracking`. `CreateWrappedUrl*` is
  documented as its drop-in replacement.

**What V2 actually does**

- `PostingService.CreatePostingAsync` → `PostingCreateCommands.CreatePostingAsync` →
  `WriteBundlePostings` (media-package / bundle) or `WriteSinglePosting`.
- Confirmed: **no wrap anywhere in that path.** The only side effect is the SNS
  `PostingNotification` fired from `PostingService`, after the command returns.

**Two constraints the ticket does not mention**

- **V2 create runs inside `ExecuteInTransactionWithRetryAsync`** (`PostingCreateCommands.cs:272`).
  It is an EF execution strategy (`EnableRetryOnFailure`, activated by CBS-4124) that clears the
  change tracker and **replays the entire delegate** on a transient failure. Consequences for the
  ticket's proposed fix:
  - anything placed inside that delegate can execute **more than once**;
  - a raw `SqlCommand` on its own connection inside the delegate sits **outside** the EF transaction
    and would contend with the still-uncommitted `jobs_sites` row.
- **The V1 wrap code is not reachable from DataAccess.** `IAnalyticsService` lives in
  `CoreAPI.Endpoints.V1/Core/Services/`, and `IDataAccess` in `CoreAPI.Endpoints.V1/Core/Common/`.
  `PostingCreateCommands` is `internal static` in `CoreAPI.DataAccess` with no DI at all. V1 already
  depends on DataAccess, so referencing V1 from DataAccess would invert the dependency. **This is a
  port, not a reference** — or the seam moves (see Q3).
- Mitigating: `PostingService` (the DI'd caller, `CoreAPI.DataAccess/Services/PostingService.cs:129`)
  **already holds `_hostedApplySettings` and `_clickToApplySettings`** — so the hash salt and the
  click2apply base URL are already in scope one level above `PostingCreateCommands`.

**Two things I found that are not in the ticket**

- **A third unwrapped `jobs_sites` writer.** `OrderCommands.AddOrderItemAsync`
  (`CoreAPI.DataAccess/Features/OrderFeatures/OrderCommands.cs:385` and `:505`) constructs
  `JobSiteEntity` rows directly — `Source = posted`, `Active = false`, `Primary = true` — never
  touching `PostingCreateCommands`. It is exposed live as
  `POST /api/experiments/job/{jobId}/order` (`CoreAPI.Endpoints.Experiments`, registered in
  `Program.cs:282` and published to the `experiments` Swagger group). Fixing only
  `PostingCreateCommands` would leave this path unwrapped.
  - **Unknown:** whether prod traffic actually reaches it. Needs the MSSQL check below.
  - Weaker than it first looked — the live partner-api order path per the ticket is
    partner-api's *own* `OrderService.CreateOrderAsync` calling core-api `POST /api/v2/posting`,
    which does go through `PostingCreateCommands`. This is a separate, experimental endpoint.
- **A test seam already exists:** `CoreAPI.Test/Service_Tests/PostingCreateCommands_Tests.cs`.

**Repo commands** — now **pinned in [[protocols/coding-standards.md]]**, the only copy. Verified
green 2026-09-17 (367/367). Do not restate the command or its container precondition here.

## Decisions

Phase 1 still in progress — Q3 onward are unanswered. Do not let a Planner read past Q2 as a spec.

- **Q1 — decided 2026-09-17: (c) decide direction now, gate Phase 2 on the query.** Not (a).
  The wrap-rate query is load-bearing for *where* the fix goes, so it does not get written off as
  "noted and unrun"; it becomes a required check before Phase 2 ships. Confirmed unobtainable today:
  all three `*-64recs-mssql` MCP servers timed out, and Grafana carries no SQL Server datasource
  (10 datasources checked — AMP, CloudWatch, X-Ray, 5 × Athena, 2 × Infinity).
- **Q2 — decided 2026-09-17: (d) inline wrap at V2 create, and re-point the Phase 2 gate.**
  Direction is "fix at create". The gate from Q1 is **replaced** by a sharper query: for the 13+22
  affected postings, does a `job_employanalytics` row exist at all, and what are
  `p_sites.is_pending_tracking` and `r_members_settings_employanalytics.apply_url_masking`?
  Reasoning: the sproc facts below show three distinct causes of a null `clickToApplyUrl`, and the
  ticket names only one. The wrap rate can flip *where* the fix goes; the null-cause breakdown can
  flip *whether this is the right fix at all*. Same blocked server, strictly more decisive.
- **Q3 — RE-DECIDED 2026-09-18 by Neru, after GATE 2: (i) in-transaction, placed *before*
  `GetPostingAsync`.** Reverses the 2026-09-17 decision, which is struck through below and kept as the
  record of what was thought at the time.

  Why it flipped — three things changed, none of them opinion:

  1. **GATE 2 retired the doom risk.** No `XACT_ABORT`, no nested transaction, no `TRY…CATCH`, no
     `RAISERROR`, no `INSERT … EXEC`, no trigger on `job_employanalytics`. Ordinary errors stay
     statement-level and committable; only deadlock 1205 dooms the transaction, and it **already does
     so today** through the existing statements, with the execution strategy already replaying it.
     See [GATE 2 — live re-read](#gate-2--live-re-read-2026-09-18).
  2. **The self-deadlock objection was against a seam nobody is proposing.** The struck entry below
     argues against a raw `SqlCommand` **on its own connection**. `Database.ExecuteSqlRawAsync`
     enlists in the *same* transaction, so the `select js.site_id from jobs_sites` read sees the
     transaction's own writes. No self-block, no NULL `@site_id`, no silent no-op.
  3. **Seam (ii) cannot fix the reported symptom without extra scope.** The hash is read inside the
     transaction at `PostingCreateCommands.cs:197-198`, so a post-commit wrap leaves
     `clickToApplyUrl` **and** `hostedApplyUrl` null on the create response *and* in the SNS `Create`
     payload — the exact thing CBS-4436 reports. Seam (i) makes both correct with no extra code.

  **Costs accepted, on the record:**

  - Larger lock footprint on a transaction that is already deadlock-prone. Judged second-order
    against the multi-table graph read it already performs per posting *and per bundle child*.
  - `Database.ExecuteSqlRawAsync` has **zero precedent in this repo** — first of its kind, not a
    tidy-up. The Reviewer should treat it as new pattern, not boilerplate.
  - ⚠️ **Planner rider:** the non-fatal wrap must **re-throw on a dead transaction**
    (`SqlException.Number == 1205` / `XACT_STATE() = -1`), not blanket-swallow. Swallowing and falling
    through to `CommitAsync` turns a retryable deadlock into a failed create.

  ⚠️ **Q4's recorded *reasoning* is now invalid, though its conclusion may still be right.** Q4 chose
  non-fatal and called it **forced** — "post-commit the posting exists and the SNS notification has
  already fired, so failing would invite a duplicate-posting retry". At seam (i) that is no longer
  true: an in-transaction failure rolls back cleanly and leaves nothing behind, so "fail the create"
  is a live option again. Non-fatal is still defensible on its own merits (a missing analytics hash
  should probably not block a job going live) — but it is now a **choice, not a consequence**, and
  nobody has made it on those terms. **Not re-decided here. Neru's call.**
- ~~**Q3 — decided 2026-09-17: (ii) post-commit in `PostingService.CreatePostingAsync`.** Not (i).~~
  Seam (i) is not merely risky — `usp_CreateWrappedUrl` reads
  `select js.site_id from jobs_sites js where js.id=@posting_id` with **no `NOLOCK`**, so a raw
  `SqlCommand` on its own connection inside `ExecuteInTransactionWithRetryAsync` blocks on the lock
  held by the transaction that is waiting for the sproc — **self-deadlock** — or resolves to no row,
  making `@site_id` NULL → `@is_pending_tracking = isnull(NULL,0) = 0` → **silent no-op**. It can
  fail closed and look exactly like the bug being fixed.
  - Corrected: (ii) does **not** save a round-trip. `Posting` has no `RecruiterId`, so the targets
    query is needed either way. The doc previously implied otherwise.
  - Still open, carried from the original framing: is there a reason the ticket proposed (i) that I
    know and the code does not show? Nothing found in the repo supports (i).
- **Q4 — decided 2026-09-17: (b) non-fatal, with a structured alertable event.**
  "Fail the create" was **eliminated by Q3, not chosen against**: post-commit the posting exists and
  the SNS `Create` notification has already fired, so returning a `CreatePostingErrorCode` would
  invite a caller retry and **duplicate the posting**. Non-fatal is forced.
  - Loudness is the real decision. V1's plain swallow reproduces the invisibility that created this
    ticket; core-api logs age out in ~15 days while the failure mode is measured in months.
  - Implementation: a structured Serilog event with a stable name, riding the
    `Serilog.Sinks.OpenTelemetry` 4.1.1 sink already referenced. **A custom metric was rejected as
    scope** — there is no hand-rolled metric anywhere in the repo today.
  - ⚠️ `PostingService` has **no logger at all** — six ctor deps, none logging. A new
    `ILogService` dependency is required. That is the repo convention in this folder
    (`HealthService.cs:15,21`), not `ILogger<T>`.
  - **This decision is only honest if the alert actually gets built.** If it will not be, revisit and
    pick plain log-and-swallow rather than ceremony.
- **Q5 — decided 2026-09-17: (a) move the wrap into a DataAccess service; V1 delegates to it.**
  V2 wraps the full target set — parent **plus** media-package children.
  - Forced by the boundary: `WriteBundlePostings` writes children but **returns `parentResult` only**
    (`PostingCreateCommands.cs:254`), so child posting IDs never reach `PostingService`. The doc's
    earlier idea of wrapping children as they are written required seam (i) and is dead.
  - Rejected — **(b) copy the UNION query into DataAccess**: leaves two copies of a hand-tuned
    174M-row query whose own comment forbids simplifying it. Drift would be silent and would surface
    as partially-wrapped bundles months later — this ticket's exact failure class.
  - Rejected — **(d) return child IDs from `WriteBundlePostings`**: cheapest at runtime, but V1 and
    V2 would then define "wrap targets" differently.
  - Rejected — **(c) wrap the parent only**: leaves bundle children unwrapped, the same gap class.
  - Key enabler: **V1 already depends on DataAccess**, so moving the logic *down* keeps the
    dependency direction valid — no inversion, no duplication, V1 behaviour unchanged.
  - Cost accepted: touches three V1 call sites — `JobService.cs:415`, `JobService.cs:831`,
    `AnalyticsController.cs:109`.
- **Q6 — decided 2026-09-17: (a) accept one sproc round-trip per child posting.**
  Mostly resolved by reading the sproc rather than by choosing: idempotency is confirmed
  (`@id IS NULL`), and non-tracking sites are genuine no-ops. Remaining cost is bounded only by data
  — `WriteBundlePostings` iterates `productBundle.ChildProducts` with **no cap in code**.
  Accepted because V1 already does exactly one sproc call per target on every prod create, and at
  seam (ii) these run post-commit, so they do not extend transaction lock hold time.
  Rejected: a batching sproc / TVP (speculative, new DB object) and deferring children to a
  background path (second execution path, new silent-failure class).
- **Q7 — decided 2026-09-17: (b) leave the third writer out of this ticket; file removal separately.**
  **Resolved with evidence, not judgement.** See "Athena ALB evidence" below.
  `POST /api/experiments/job/{jobId}/order` is live, ungated and publicly routed, but has **not been
  called in 200 days**. Wrapping it would be harmless but pointless; the real finding is **dead code
  exposed in prod**. Record the evidence, raise a separate ticket to gate or remove the Experiments
  assembly.
  - Superseded my own earlier recommendation to fold it in — that argument was explicitly
    conditional on traffic being unknown.
- **Q8 — decided 2026-09-17: (a) run `/internal/analytics/RegisterJobs` now, as the gate experiment.**
  This is **not just remediation** — it is the Q2 gate, and it needs **no MSSQL**.
  `RegisterJobs` → `RunJobsAsync` → `CreateWrappedUrlsForPostingAsync` per posting
  (`AnalyticsController.cs:44-45`, `:107`) — the exact code path the fix will use, idempotent via
  the sproc. The three causes respond differently, so the flip count partitions them:
  | Cause | After `RegisterJobs` |
  | --- | --- |
  | 1 — row never created, site opted in, apply URL resolvable | row created → **`clickToApplyUrl` non-null** |
  | 2 — `is_pending_tracking = 0` | sproc no-ops → **stays null** |
  | 3 — row exists, `tracking_url` NULL | `@id` not null → sproc no-ops → **stays null** |
  - **Procedure:** `GET /api/v2/posting/{id}` for each → `POST /internal/analytics/RegisterJobs`
    → `GET` again. `clickToApplyUrl` is readable over HTTP, so no DB access is required.
  - Splits cause 1 from causes 2/3. It does **not** separate 2 from 3 — both stay null — but that is
    not the decision-relevant question. If most flip, the direction chosen in Q2 holds. **If few flip,
    the ticket's root cause is wrong and Q2 must be reopened.**
  - No evidence is destroyed: the ones that flip are cause 1 by definition, and MSSQL can still split
    the remainder later.
  - ⚠️ **Prod write. Not to be run without Neru asking for it in the same breath.**
  - **Blocked on credentials, 2026-09-17 — not on access.** Every core-api request requires an
    `X-API-KEY` header (repo `CLAUDE.md:114`; `Program.cs:370` registers
    `ApiKeyAuthenticationDefaults`, `:399` `UseAuthorization()`). The agent does not hold a prod key
    and **deliberately did not go looking for one** — pulling prod credentials into context is
    exactly what the secret-safety rule forbids. **Neru runs this; the key stays in his environment.**
  - Routing confirmed reachable: `/internal/analytics/*` is **publicly routable through the prod
    ALB**, not VPC-only — `POST /internal/analytics/fixurlnotwrapped` took **7,012 calls from 46
    distinct client IPs** in 2026/09/01–16. `RegisterJobs` sits on the same prefix.
  - Payload shape (`AnalyticsRequest`): `{"postings":[<int>,...],"encodeUrl":false}`.
  - Runner written and syntax-checked: `cbs4436-experiment.ps1` — Phase A read-only by default,
    prod write only under `-Execute`, key read from `$env:CORE_API_KEY`, never persisted.
    **The 22 spider posting IDs are not in the ticket** — the script resolves them from
    `GET /api/v2/job/{jobId}/posting` for jobs 41067728 / 41063570 / 41063651, and prints a warning
    if the total is not 35.
- **Q9 — decided 2026-09-17: split the ats-api `ThreadAbortException` wrap bug into its own ticket.**
  Deciding fact is ownership, not the failure mode: **`atsapi-v6` is in the Unassigned list** in
  [[README.md]], not under CBS or AS — and the rule for that list is to ask, not assume. Folding an
  unassigned-repo fix into a CBS ticket routes it past whoever owns it.
- **Testing — decided 2026-09-17: (b) unit + integration.**
  Q3 and Q5 changed this: with the wrap behind an injectable DataAccess service called from
  `PostingService`, the seam is mockable — the doc's earlier worry that "a raw sproc call is awkward
  to unit test" applied to seam (i), which is dead.
  - **Unit:** the non-fatal contract from Q4 — a throwing wrap does **not** fail the create, and the
    structured event fires. No DB. This is the behaviour most likely to regress silently.
  - **Integration:** the relocated UNION targets query still returns parent **plus** media-package
    children. Needs the repo's `mcr.microsoft.com/mssql/server:2019-latest` container path.
  - ✅ **Container path verified 2026-09-17.** `docker start coreapi-test-sql` →
    `dotnet test CoreAPI.Test/CoreAPI.Test.csproj` → **367/367 green, 5m40s**. The earlier
    192-failed baseline was **100% environmental** — a single
    `OneTimeSetUp: SqlException` bucket, zero real assertion failures. So (b) is genuinely
    available and does not degrade to unit-only. Command pinned in
    [[protocols/coding-standards.md]] — the only copy.
- **Process — decided 2026-09-17: do NOT use the bypass labels for this change.**
  The ticket carries `MR_bypass`, `MRbypass`, `Mr_bypass`, `UAT_Bypass`, `mrbypass`, `noqarequired`.
  They were applied to the ticket's *original* plan — one sproc call inside `PostingCreateCommands`.
  After this session the change is a new DataAccess service, a relocated hand-tuned 174M-row query,
  **three V1 call sites**, and a new ctor dependency on `PostingService`. That is materially larger,
  and it touches the V1 path this ticket treats as the working reference.
  - Not a judgement that the labels are wrong — they were set for a different plan.
  - Minor: `MR_bypass` / `MRbypass` / `Mr_bypass` / `mrbypass` are **four case variants of one label**
    (Jira labels are case-sensitive). Sprawl, not four signals. Worth tidying; changes nothing.

## Athena ALB evidence — `/api/experiments/` traffic

Run 2026-09-17 against the **`athena-alb-prod`** Grafana datasource (`alb_logs.alb_access_logs`,
`s3://prod-consolidated-elb-logs`). This is a **live read**, unlike the sproc DDL above.

- Prod core-api ALB identified as account **`245228264023`**, elb `app/alb-prod-core-api/bd1e7e863489bd8f`
  (98,782 `/api/v2/posting` hits on 2026-09-16 alone).
- Table uses **partition projection**, `day` format `yyyy/MM/dd`, range `2025/06/01 → NOW` — so ALB
  history reaches back **over a year**, far beyond the ~15-day core-api log retention.

| Check | Window | Result |
| --- | --- | --- |
| `url_extract_path LIKE '/api/experiments/%'` | 2026/03/01–2026/09/16 (200d) | **0 rows** |
| loose `lower(request_url) LIKE '%experiment%'` | 2026/09/01–16 | 15 hits, **all false positives** |
| control `url_extract_path LIKE '/api/v2/%'` | 2026/09/01–16 | 39.3M on `/api/v{id}/job/{id}` alone |
| total requests sampled | 2026/09/01–16 | 133,237,411 |

- The 15 loose hits are all the same daily ~23:00 probe from an internal `node` client on
  `10.70.46.x`: `GET /api/v2/user/search?emailAddress=einsteinexperiment%40googlemail.com`. The
  substring is coincidental.
- The control proves the predicate shape is sound, so the zero is a real zero, not a broken filter.
- ⚠️ **Caveat that cannot be closed from these logs:** ALB logs capture only traffic *through the
  ALB*. A VPC-internal caller hitting the service directly would not appear. No evidence such a path
  exists; it is also not ruled out.
- ⚠️ Two Athena queries in a single `/api/ds/query` call returned **504**. Run them one per call.

## Rejected

- **Nothing rejected yet.** Options are enumerated under Q2/Q3 below, all still live.

## Sproc facts

**✅ LIVE-VERIFIED 2026-09-18 (GATE 2).** Originally read 2026-09-17 from the DataGrip prod cache
(snapshot 2026-07-08) while MSSQL MCP was down. Re-read live against `prod`, `uat` **and** `qa`
`64recs67o`: `usp_CreateWrappedUrl` is **byte-identical across all three** (bar one space in the
`create  procedure` header) and carries the same `DBA-2476 / 20260527` version the snapshot showed.
**The cache was faithful — everything below stands, including the three-causes finding that drove Q2.**
No environment drift. See [GATE 2 findings](#gate-2--live-re-read-2026-09-18).

### `dbo.usp_CreateWrappedUrl` — the ticket's Q6 premise is only half right

Idempotency is real (`if @id is null` on an existing active row), but it is an **`AND`**:

```sql
if @id is null and @is_pending_tracking = 1
```

- **An unconditional wrap at create does not fix every null.** Sites with
  `p_sites.is_pending_tracking = 0` get no row at all — correctly, by design. Null
  `clickToApplyUrl` for those is not a bug.
- **Even when the row is inserted, `tracking_url` can still be NULL:**
  `SET @tracking_url = IIF(@is_masked=1, 'https://www.click2apply.net/'+@hash, NULL)`.
  `@is_masked` is 0 when `@apply_url` resolves empty through all three fallbacks
  (`jobs_info_medium` item 70 → `usp_oneclick_posting_custom_apply_url` → job-wide item 70), or
  when the recruiter has `r_members_settings_employanalytics.apply_url_masking = 0`. Masking
  defaults **on** (`isnull(...,1)`), so the dominant cause is an unresolvable apply URL.
- ⚠️ Adjacent-column trap: a *different* `p_sites` BIT, `is_pending_update_required`, has
  **inverted** semantics (1 = skip). `is_pending_tracking` is **not** inverted — 1 means opt **in**.
  Do not carry the inversion across.

**Three distinct causes of a null `clickToApplyUrl`, and the ticket names only one:**

1. Row never created — the ticket's diagnosis.
2. Row not created because the site opted out (`is_pending_tracking = 0`) — correct behaviour.
3. Row created but `tracking_url` NULL — no resolvable apply URL, or masking off.

**Cause 3 is a permanent sweep-churn bug.** `usp_get_jobs_applyurl_not_wrapped` selects on
`LEFT JOIN ... WHERE je.tracking_url IS NULL`, which matches both "no row" *and* "row with null
`tracking_url`". For the latter, `@id` is not null, so `usp_CreateWrappedUrl` no-ops. The sweep
re-finds those postings every cycle and can never fix them. Not in the ticket.

### `PM.usp_get_jobs_applyurl_not_wrapped` — widening is not a one-line change

- The `#temp` stage is **already channel-agnostic**: every active, non-expired `jobs_sites` with a
  null `tracking_url`, no campaign gate. The narrowing happens *after* it.
- The result set is **campaign-shaped** — `campaign_job_id`, `campaign_name`, `campaign_cycle_id`,
  `campaign_id`, all sourced from `cp` and its cycle joins. Drop `campaign_posting` and there is no
  `campaign_job_id` to return: **the PostMaster consumer contract breaks.** One sproc *plus* its caller.
- It returns **campaign job IDs, not posting IDs** — so it is not even shaped to drive a
  per-posting wrap without a rewrite.
- `#temp` is an unbounded scan of active `jobs_sites` (with `forceseek` hints). Un-narrowed, the
  output could be very large.

### GATE 2 — live re-read 2026-09-18

Two things were asked of GATE 2. Both are answered.

**(a) Snapshot fidelity — PASS.** Covered in the preamble above. No drift, prod/uat/qa identical.

**(b) Does a SQL error inside `usp_CreateWrappedUrl` doom the transaction? — NO, except deadlock,
and deadlock already dooms it anyway.** This was *the* live risk against seam (i). It is retired.

Read from `sys.sql_modules` and `sys.triggers` on prod, not inferred:

| Property | `usp_CreateWrappedUrl` | nested `usp_oneclick_posting_custom_apply_url` |
| --- | --- | --- |
| `SET XACT_ABORT` | absent | absent |
| `BEGIN TRAN` | absent | absent |
| `TRY…CATCH` | absent | absent |
| `RAISERROR` / `THROW` | absent | absent |
| `INSERT … EXEC` nesting (would be error 8164, batch-aborting) | n/a | **absent** |

- **No trigger on `job_employanalytics`.** The only trigger across the three tables the sproc touches
  is `trg_p_sites_after_insert` on `p_sites`, which the sproc only *reads*. No hidden doom path.
- Nothing sets `XACT_ABORT ON`, and SqlClient's default is OFF. So ordinary errors are
  **statement-level**: `XACT_STATE()` stays `1`, the transaction remains committable, and Q4's
  "catch, log, continue → `CommitAsync`" works exactly as written.
- The NOT NULL columns are **not** a failure mode. `hash` and `img_url` are both NOT NULL, but V1
  computes both from the generated hash and neither can be null
  (`CoreAPI.Endpoints.V1/Core/Services/AnalyticsService.cs:192-193`, HEAD `fcf24ca5`). Error 515 is off
  the table.
- What survives `XACT_ABORT OFF` as genuinely doom-class: **deadlock 1205** and severity ≥ 17.
  **But 1205 already dooms the create transaction through its existing statements** — `jobs` is the
  documented chronic victim (`CoreAPI.DataAccess/Features/JobFeatures/Common.cs:40-42`) — and
  `CreateExecutionStrategy()` + `EnableRetryOnFailure()` exist precisely to replay it
  (`PostingCreateCommands.cs:277-283`). **Seam (i) introduces no doom class the transaction does not
  already carry.** It enlarges the lock footprint of an already-deadlock-prone transaction; it does
  not add a new kind of failure.

⚠️ **Rider that must reach the Planner.** Q4's "non-fatal wrap" cannot be a blanket
`catch (Exception) { log; continue; }` at seam (i). On a doomed transaction, swallowing the error and
falling through to `CommitAsync` throws anyway — turning a retryable deadlock into a failed create.
The catch has to **re-throw when the transaction is dead** (`SqlException.Number == 1205`, or
`XACT_STATE() = -1`) so the execution strategy replays, and swallow only the committable cases.

#### Also found: the PostMaster sweep degrades silently

`PM.usp_get_jobs_applyurl_not_wrapped` wraps its whole body in `TRY…CATCH`, and the `CATCH`
**`SELECT`s the error columns as a result set** instead of rethrowing (`ERROR_NUMBER()`,
`ERROR_MESSAGE()`, …). So a failure inside the sweep returns *a row*, not an exception.

- To a caller expecting "the list of jobs still needing a wrap", **a broken sweep is indistinguishable
  from a clean one that found nothing.** The backstop can be dead without anyone being paged.
- Not in CBS-4436's scope, but it undercuts "the PostMaster sweep will catch it" as a safety argument
  anywhere in this doc. Flag it; do not lean on it.

### GATE 1 — answered by DB state 2026-09-18

**The specified experiment can no longer be run, and no longer needs to be.** It was to POST the 35
affected postings to `/internal/analytics/RegisterJobs` and count how many flipped. **34 of the 35 have
since been remediated**, so the flip-test has a sample of one. The underlying question was instead
answered directly against prod `64recs67o` — read-only, and stronger evidence than the flip count
would have been.

Also learned in passing: **core-api did not enforce `X-API-KEY` on these prod GETs.** The credential
that blocked this gate for three sessions was never actually required. Flagged as a finding, not used
as a licence — nothing was written.

#### The 13 "posted" cohort — unambiguous

| Fact | Value | What it kills |
| --- | --- | --- |
| `p_sites.is_pending_tracking = 1` | **13 of 13** | **Cause 2 (site opted out) is eliminated.** Every one of them should have had a row. |
| `apply_url_masking = 1` on the created rows | **12 of 12** | **Cause 3 (nothing maskable) is eliminated.** |
| Analytics row created *after* the posting | **12 of 12, by 10–19 days** | The row was **missing at create** and added later. **Cause 1 confirmed.** |
| Analytics row still absent today | **1 of 13** (`285699513`) | The backstops never caught it — 72 days on. |

The 12 remediated rows landed in **exactly two batches** — `2026-07-17 14:56` (8 rows) and
`2026-07-20 13:15` (4 rows). That is not organic backstop behaviour; it is two manual remediation
runs. (`added` is `smalldatetime`, so identical stamps mean one batch.)

#### `285699513` is the proof case for the whole ticket

Every gate green, still unwrapped 72 days later:

- `is_pending_tracking = 1` — the site **wants** tracking.
- `jobs_info_medium item 70` returns **1 row** — there **is** an apply URL to mask.
- `job_employanalytics` — **no row at all.** Never created.
- **Not in `PM.campaign_posting`** → the PostMaster sweep's `INNER JOIN` excludes it. Exactly the
  ticket's scenario 1 (non-campaign partner-api direct order).
- `expire = 2026-07-14`, now in the past → the sweep's `js.expire > getdate()` filter **also** excludes
  it. It is now **structurally unreachable by the sweep, permanently.**

It was created at `2026-07-08 10:41`, **one minute before** `285699605` (10:42), which *was*
remediated on 07-20. It was missed by hand, and nothing automatic has ever picked it up.

**This is the strongest single argument in the ticket for wrapping at create.** The backstops are not
merely narrow — for this slice they are unreachable, and the only thing that has ever fixed these
postings is a human running a remediation script.

#### The spider cohort — consistent, weaker

All postings across jobs `41067728` (33), `41063570` (34) and `41063651` (1) now have an active
analytics row: **0 missing, 0 `tracking_url` null, 0 opted-out sites.**

⚠️ **Do not read per-posting lateness from this.** The aggregate spans re-postings of the same job over
months (`last_analytics_added` runs to 2026-09-14), so it mixes fresh postings with late-wrapped ones.
It corroborates "no site in the cohort is opted out"; it does **not** independently establish cause 1.
The 13-posting cohort carries that finding.

#### What this does and does not license

- ✅ **Q2's direction (wrap at create) and Q3's seam (i) both stand.** The root cause is a missing row
  on a tracking-enabled, maskable posting — precisely what an inline wrap fixes.
- ✅ GATE 1's stated kill condition ("if most stay null, the root cause is wrong, reopen Q2") **did not
  trigger**.
- ⚠️ **This is not the experiment that was specified.** It is a different, observational method. Neru
  should accept or reject it as satisfying GATE 1 rather than have that assumed.
- ⚠️ **No wrap-rate denominator.** This says the cohort's cause is 1; it does not say how often the
  gap occurs across all channels. That number is still unmeasured.

### The cause model was wrong — corrected 2026-09-18

Verified live on prod, independently of the subagent that first raised it.

**Cause 3 cannot produce a missing row.** Once `usp_CreateWrappedUrl` passes its two gates
(`@id is null AND @is_pending_tracking = 1`) the `INSERT` is **unconditional**. An unresolvable apply
URL only makes `tracking_url` NULL — the row still exists. So:

> **"No active `job_employanalytics` row" + `is_pending_tracking = 1` means the proc was never
> invoked.** It is a **non-call, not a no-op.** That is the correct signature for this bug, and the
> right predicate is `NOT EXISTS (any active je row)` — not `tracking_url IS NULL`.

**Cause 2 and cause 3 are both structurally empty in production:**

| Claim | Measured | Consequence |
| --- | --- | --- |
| Sites with `is_pending_tracking = 0` | **14 of 37,452** | The DBA-2476 gate filters essentially nothing. |
| Live active postings on an opted-out site | **0** | **Cause 2 does not occur.** |
| Live active postings with a row but `tracking_url IS NULL` | **0** | **Cause 3 does not occur.** |

So every unwrapped live posting is cause 1. The three-cause model in *Sproc facts* above is retained as
the *theory* of the sproc, but only one branch of it is real.

### The wrap-rate denominator — answered 2026-09-18

Q1's underlying number, never measured before this:

| Measure | Value |
| --- | --- |
| Live active postings (`js.active=1 AND js.expire > getdate()`) | **442,461** |
| Of those, with **no** active `job_employanalytics` row | **21** |
| Miss rate | **0.0047%** |

**Read this honestly in both directions.** The gap is real, reproducible and 100% cause 1 — but it is
*four thousandths of one percent* of live postings. It is not a widespread outage. Nothing in this doc
should be written as though it were. The counts drift by one or two between runs because production is
moving; treat 21 as a 2026-09-18 snapshot.

⚠️ **This covers live postings only.** Classifying all 208M `js.active=1` rows is infeasible — the MCP
server enforces a hard 60-second query cap. No claim is made about wrap state before ~2026-06.

### ⚠️ The PostMaster backstop has been dead since February 2023

**This is the most consequential finding in the ticket, and it invalidates a premise in the Jira
description.** Verified directly, not inferred:

```sql
SELECT COUNT_BIG(*), MAX(created_date), MAX(posting_id),
       SUM(CASE WHEN created_date > DATEADD(Month,-1,GETDATE()) THEN 1 ELSE 0 END)
FROM PM.campaign_posting WITH (NOLOCK)
-- 67,636,315 rows | max created_date 2023-02-21 | max posting_id 205,036,529 | 0 in the last month
```

- `PM.campaign_posting` is **frozen**. Nothing has been written to it since **2023-02-21**.
- Its highest `posting_id` is **205,036,529**. Current `jobs_sites.id` values are **~287,000,000**.
  **No posting created since Feb 2023 is in that table at all.**
- `PM.usp_get_jobs_applyurl_not_wrapped` `INNER JOIN`s that table *and* requires
  `cp.created_date > DATEADD(Month,-1,getdate())` — which matches **zero rows**. The sweep has returned
  an empty set on every run for about three and a half years.
- **Worse: the sweep never repaired anything even when it did return rows.** It is a `SELECT`-only
  report — it returns `campaign_job_id`, `job_title`, `campaign_name`, `campaign_cycle_id`,
  `campaign_id`. No `INSERT`, no `EXEC usp_CreateWrappedUrl`. Re-read from the live DDL above.

**Consequences that must reach the Planner and the ticket:**

1. **There are two backstops, not three.** The Jira description's "PostMaster scheduled sweep" is not a
   safety net and has not been one since 2023.
2. Of the two that remain, the marketplace UI only covers marketplace checkouts, and **ats-api's is
   itself broken** (fire-and-forget `Thread`, dies on `ThreadAbortException` — the PST split-out).
3. **Q2's "widen the backstop" option is worse than the doc records.** Widening
   `usp_get_jobs_applyurl_not_wrapped` would mean un-freezing a dead table *and* converting a report
   into a repair job. It was already rejected; this is further confirmation, not a reopening.
4. It explains GATE 1's `285699513` cleanly: nothing was ever going to fix it.

⚠️ **This is out of CBS-4436's scope but should not die here.** A scheduled job that has silently
returned zero rows since 2023 is its own defect, and it is not this ticket's to fix.

### GATE 1 — flip-test result (UAT, 2026-09-18)

**PASS. 20 of 20 flipped. 0 stayed null.** The gate's kill condition did not trigger; the ticket's root
cause is confirmed by the method that was actually specified.

**Run in UAT, not prod — Neru's call, and the better venue.** Validity rests on three checks, each
verified rather than assumed:

| Check | Result |
| --- | --- |
| `usp_CreateWrappedUrl` prod vs UAT vs QA | **byte-identical** (GATE 2) — the test exercises the same code |
| UAT is a genuinely separate dataset | posting `287052122` = job 41583399 / Indeed on UAT, job 40265706 / Bay East Center on prod |
| UAT had a real cause-1 cohort | **20** of 398,817 live active postings — nearly identical profile to prod's 21 of 442,461 |

Method: capture before-state → `POST https://uat-core-api.jobtarget.com/internal/analytics/RegisterJobs`
with the 20 ids → re-read. **Before: 20/20 null. After: 20/20 populated.**

Corroborated two ways, because one of them is untrustworthy:

- **The endpoint's own response is worthless as a signal** — it returned `{"status":0,"message":"success"}`,
  which `RunJobsAsync` emits unless an exception escapes two nested catch-alls
  (`AnalyticsController.cs:92-125`, `AnalyticsService.cs:212-224`). Predicted in advance; confirmed.
- **DB truth:** 20 new `job_employanalytics` rows, ids `202705814`–`202705833` — **contiguous, exactly
  20**, all `tracking_url` non-null, `wrapped_url` non-null, `apply_url_masking = 1`. The contiguity
  independently confirms no media-package children were expanded, matching the pre-check.

**Bonus corroboration of the Q3 seam argument.** UAT returned
`https://uat-click2apply.jobtarget.com/<hash>`, not the `https://www.click2apply.net/<hash>` the sproc
hardcodes into `tracking_url`. That is not a contradiction — it is `SetApplyUrls` composing the
response from **`clickToApplyBaseUrl` config + the hash read from `job_employanalytics`**
(`PostingQueries.cs:240-246`). **Observed proof that the API's `clickToApplyUrl` derives from the hash
row** — which is precisely why seam (ii) would leave the create response null, and why seam (i) fixes
it for free.

⚠️ **What this does and does not establish.** It proves the mechanism: on a posting with all gates
green, invoking the wrap creates the row and populates the URL. It does **not** re-prove that prod's 21
are cause 1 — that was measured directly from their gate state. The two together are what close the
gate.

⚠️ **Prod was not touched.** The 21 prod postings remain unwrapped. Remediating them is a separate,
deliberate act that nobody has authorised.

### Seam facts for Q3

- `PostingService` holds `_hostedApplySettings` as a field (`PostingService.cs:40`), so `HashIdSalt`
  **is** in scope at seam (ii). `CreatePostingAsync` already has a post-commit
  `result.DoRightAsync(...)` block for the SNS notification (`PostingService.cs:131-134`).
- `Posting` (`CoreAPI.Public/Domains/Posting/Posting.cs`) exposes `Id`, `JobId`, `SiteId` —
  **no `RecruiterId`**. The hash needs all four, so seam (ii) still needs the targets query.
  **It saves no round-trip over (i)** — the doc's earlier assumption that it did was wrong.
- **Seam (i) has a concrete mechanical failure.** `usp_CreateWrappedUrl` does
  `select js.site_id from jobs_sites js where js.id=@posting_id` with **no `NOLOCK`**. Inside
  `ExecuteInTransactionWithRetryAsync`, a raw `SqlCommand` on its own connection reads `jobs_sites`
  while the outer EF transaction still holds the uncommitted row — under READ COMMITTED that read
  blocks on a lock held by the transaction that is waiting for the sproc to return: **self-deadlock**.
  If it instead resolves to no row, `@site_id` is NULL → `@is_pending_tracking` is `isnull(NULL,0) = 0`
  → the `if` fails and **nothing is inserted, silently**.
- V1's `CreateWrappedUrlsForPostingAsync(postingId)` takes only a posting id and resolves
  job/site/recruiter itself via `GetWrappedUrlTargetsAsync`, then calls the sproc once per target.
  `recruiter_id` DBNull coalesces to `0` in the hash (`AnalyticsService.cs:266`).


## Implementation note — raw SQL vs LINQ for the targets query

Verified 2026-09-17 by building the LINQ rewrite and dumping the real generated SQL
(`ToQueryString()` **plus** a capture `DbCommandInterceptor` registered after `AddQueryHints()`,
executed against the local `coreapi-test-sql` container). Scratch fixture deleted afterwards.

**The initial objections to LINQ were wrong.** Both are already solved in this repo:

- `.WithHint(TableHint.Nolock)` exists — `CoreAPI.DataAccess/Interceptors/QueryHintInterceptor.cs`,
  already used in `JobFeatures/Common.cs:47` and `OrderQueries.cs:74`.
- The varchar/nvarchar sargability trap is closed: `JobFeatureEntity.Value1` is `.IsUnicode(false)`
  with a comment citing **CBS-4432**. Confirmed — EF emits `@__postingIdText_1 varchar(100)`.

**The UNION shape translates correctly.** Two independently seekable branches, same join structure,
a real `UNION` — not the `OR` form the V1 comment forbids.

**But `WITH (Nolock)` only lands on the `FROM` tables, never on a `JOIN`.** The interceptor's regex
matches `FROM x AS y` only — the alternation covers whitespace/CR/LF between the tokens,
but there is no `JOIN` branch in the pattern at all. See `QueryHintInterceptor.cs` for the
literal expression; it is not reproduced here because its escapes do not survive markdown.

| Table reference | V1 raw SQL | LINQ + `WithHint` |
| --- | --- | --- |
| `jobs_sites` (branch 1 FROM) | NOLOCK | **NOLOCK** |
| `jobs` (branch 1 LEFT JOIN) | NOLOCK | **none** |
| `jobs_features` (branch 2 FROM) | NOLOCK | **NOLOCK** |
| `jobs_sites` (branch 2 INNER JOIN) | NOLOCK | **none** |
| `jobs` (branch 2 LEFT JOIN) | NOLOCK | **none** |

Three of five references would take shared locks V1 does not — on every posting create, against
`jobs`, the table `JobFeatures/Common.cs:39` documents as *"the chronic deadlock victim against
concurrent job writes (SqlException 1205)"*.

**Decision: keep raw SQL for the targets query**, with a comment citing the interceptor limitation so
this is not re-litigated. The sproc call still moves to `Database.ExecuteSqlRawAsync` — EF has no
stored-procedure API, but that removes all the `DbCommand` / reader / connection-lifecycle plumbing.

Two by-products:

- **EF Core 7 cannot `Union` after a positional-record projection** —
  *"Unable to translate set operation after client projection has been applied."* An anonymous-type
  projection is required, mapping to a named type client-side after `ToListAsync`.
- ⚠️ **`OrderQueries.cs:74` uses `.WithHint(TableHint.ForceSeek)`** and is subject to the same
  FROM-only limitation. If that query joins, only its FROM table is being hinted. **Pre-existing, not
  introduced by CBS-4436 — worth its own look.**
- `JobEntity.DivisionId` maps to column **`recruiter_id`** (`JobEntity.cs:54`). V1 calls this value
  `recruiterId`; `HostedApplyUrlGenerator.cs:76` calls the same column `divisionId`. Same column,
  same hash input — "correcting" either name would change every hash ever generated.

## Scope

**In** — provisionally, pending Q1/Q2:

- `CoreAPI` only.
- The V2 posting create path and where a wrap belongs relative to it.

**Out** — provisionally:

- The immediate remediation of the already-affected postings. The ticket says these can be fixed
  now by POSTing their posting IDs to `/internal/analytics/RegisterJobs` (idempotent, all gates
  green). That is independent of this discovery — see Q8.

## Blockers

- **All three MSSQL MCP servers failed to connect on 2026-09-17** (`qa-`, `uat-`, `prod-64recs-mssql`,
  all `CONNECT_TIMEOUT` at 30s). Connection failure, not missing access. Consequence:
  - the ticket's discovery question 1 (per-channel wrap rate on prod `64recs67o`) **could not be run**;
  - could not check which code path created the affected postings (e.g. `285573508`);
  - could not check whether `POST /api/experiments/job/{jobId}/order` sees prod traffic.
- DataGrip cached-DDL fallback covers schema only, not row data — no help for the wrap-rate number.

## Open questions

**Q1–Q9, testing and process are all RESOLVED — see [Decisions](#decisions), which carries each
answer and its reasoning.** They are deliberately not restated here; one fact, one home.

The `OPEN QUESTION` marker below is load-bearing: the Planner stops on it
([`coding/four-agent-pipeline.md`](../coding/four-agent-pipeline.md)). Only genuinely unresolved
items carry it.

- ~~**OPEN QUESTION — Q4's failure semantics must be re-confirmed on seam (i)'s terms.**~~
  — **CLOSED 2026-09-18. Neru re-confirmed NON-FATAL, now on seam (i)'s terms.** Not inherited from
  the old reasoning, which was void: it is chosen because a missing analytics hash should not stop a
  job going live, and GATE 1 evidence shows the row can be created later without harm. **The GATE 2
  rider still binds** — the catch must re-throw on a dead transaction
  (`SqlException.Number == 1205` / `XACT_STATE() = -1`) so the execution strategy replays; only
  committable failures may be logged and swallowed. *Original framing kept below.*
  Opened 2026-09-18 by the Q3 re-decision; it was **the only thing still blocking Phase 2.** Q4 chose
  *non-fatal* and recorded it as **forced** — "post-commit the posting exists and the SNS `Create`
  notification has already fired, so failing would invite a caller retry and duplicate the posting".
  At seam (i) that is false: an in-transaction failure rolls back cleanly and leaves nothing behind,
  so **"fail the create" is a live option again.** Non-fatal remains defensible on its own merits — a
  missing analytics hash should probably not stop a job going live, and GATE 1 shows the row can be
  added later — but it is now a **choice, not a consequence**, and nobody has made it on those terms.
  **Neru decides.** Whichever way it goes, the GATE 2 rider still binds: the catch must re-throw on a
  dead transaction (`SqlException.Number == 1205` / `XACT_STATE() = -1`), never blanket-swallow.

- ~~**OPEN QUESTION — GATE 1 IS NOT SATISFIED.**~~ — **CLOSED 2026-09-18. GATE 1 PASSES, 20/20.**
  The specified flip-test was run, on the method Neru required, in **UAT** (his call — better venue
  than prod). See [GATE 1 — flip-test result](#gate-1--flip-test-result-uat-2026-09-18).
  **No `OPEN QUESTION` markers remain. Phase 2 is unblocked.**

- ~~*(superseded)* **GATE 1 IS NOT SATISFIED. Neru rejected the substituted method 2026-09-18.**~~
  The DB-state evidence below stands as *evidence* and is not withdrawn — but it is **not** the
  flip-test the gate specified, and Neru declined to accept it in place of one. **GATE 1 therefore
  still blocks Phase 2.**
  - The original 35-posting cohort **cannot** serve: 34 are remediated, leaving n=1. Re-running the
    specified experiment on it would produce no signal for anyone.
  - **Cohort rebuilt 2026-09-18 — 21 live cause-1 postings**, every gate green, none in
    `PM.campaign_posting`. 17 of 21 are on site 25393 (JobTarget Programmatic); the rest are
    Socialworkerjobs.com (2), Indeed Sponsored Campaign (1), PracticeMatch (1). Sample IDs and the
    denominator are in [the wrap-rate section](#the-wrap-rate-denominator--answered-2026-09-18).
  - **Remaining step is the flip-test itself**, which is a **prod write**
    (`POST /internal/analytics/RegisterJobs`). **Not made.** It requires Neru to ask for that write in
    the same breath; "run the experiment" does not imply it. Re-run the cohort query immediately
    before firing — the count drifts as production moves.

- ~~*(superseded framing)* **GATE 1: the `RegisterJobs` flip-count experiment has not been run.**~~
  — DB-state answer recorded 2026-09-18, **not accepted as satisfying the gate.**
  See [GATE 1 — answered by DB state](#gate-1--answered-by-db-state-2026-09-18). **Verdict: the
  ticket's root cause HOLDS. Cause 1 confirmed, causes 2 and 3 eliminated for the whole cohort.
  Q2's direction and Q3's seam both stand. Phase 2 is unblocked on this axis.**
  *Original text kept below — it is what the gate was supposed to do.*
  Blocked on credentials, not access — core-api requires `X-API-KEY`; Neru runs it, the key stays in
  his environment. Runner: `cbs4436-experiment.ps1` (read-only by default, prod write under
  `-Execute`). **This can invalidate the entire direction:** if most of the 35 postings stay null,
  the ticket's root cause is wrong and Q2 must be reopened before any implementation.

- ~~**OPEN QUESTION — GATE 2: both sprocs were read from a 2026-07-08 DataGrip cache snapshot, not
  live.**~~ — **CLOSED 2026-09-18.** Re-read live against prod, uat and qa `64recs67o`. The snapshot
  was faithful (no drift, all three identical), and the doom-transaction question is answered: **no,
  except deadlock, which already dooms the transaction anyway.** Full findings and the catch-rethrow
  rider in [GATE 2 — live re-read](#gate-2--live-re-read-2026-09-18). **Q3 is now unblocked.**

- ~~**OPEN QUESTION — Q3 IS REOPENED. The recorded reasoning does not survive review.**~~
  — **CLOSED 2026-09-18. Re-decided: seam (i), in-transaction, before `GetPostingAsync`.** Reasoning
  in [Decisions](#decisions). The review evidence that reopened it is kept below, unedited, because it
  is what drove the reversal. **A follow-on opened in its place: Q4's reasoning no longer holds — see
  the Q4 note in Decisions.**
  **Deferred by Neru 2026-09-18 until GATE 2 landed. GATE 2 HAS NOW LANDED (same day)** — the
  doom-transaction question came back **in seam (i)'s favour**: no new doom class, deadlock excepted
  and already handled by the execution strategy. The last technical objection to seam (i) is gone, and
  seam (ii) still leaves the create response and the SNS payload null (below). **Q3 is decidable now
  and still Neru's call — it remains Phase 2's hard prerequisite.**
  Investigated 2026-09-17 (session 4) against `CoreAPI` HEAD `fcf24ca5` — the same commit the rest of
  this doc cites. Every line below was read, not inferred. **Neru decides; no decision reached.**

  **The three surviving arguments for seam (ii) do not hold as written:**

  | Argument | Verdict | Evidence |
  | --- | --- | --- |
  | Retry replay | **WEAKENED** | `PostingCreateCommands.cs:277-283` — the whole delegate replays, including `BeginTransactionAsync`. But replay only follows a rollback, so an *in-transaction* wrap is rolled back with it and re-done atomically. No double-insert; the sproc is idempotent besides. This argues against a raw `SqlCommand` on its own connection — the seam the re-look already discards. |
  | Lock-hold time | **WEAKENED** | The transaction already holds a multi-table graph read per posting — `GetPostingAsync` at `PostingCreateCommands.cs:197-198`, spanning `JobSiteStatuses`, `JobEmployAnalytics`, `Job→Division→Company→PartnerSite`, `JobFeatures`, `OrderItems` (`PostingQueries.cs:44-89`), once per parent *and every bundle child*. One sproc round-trip is second-order against that. `CommandTimeout` 30s (`DataContextConfiguration.cs:11`). |
  | Q4 non-fatal only coherent post-commit | **REFUTED as stated** | "A failing wrap must not fail the create" is achievable in-transaction: catch, log, continue, let `CommitAsync` run (`PostingCreateCommands.cs:292`). The sub-claim that failure would invite a duplicate-posting retry is *only* true post-commit — an in-transaction rollback leaves nothing behind. |

  **New fact neither option accounted for — this is the decision-relevant one:**

  - **Seam (ii) leaves the create response and the SNS payload still null.** `Posting.ClickToApplyUrl`
    derives from the `job_employanalytics.Hash` read at `PostingQueries.cs:50-55`, via `SetApplyUrls`
    (`:95` → `:240-246`, `postingHash is null ? null : …`). That read happens **inside** the
    transaction (`PostingCreateCommands.cs:197-198`), strictly before any post-commit wrap.
  - Consequence: `POST /api/v2/posting` returns `clickToApplyUrl: null` **and** `hostedApplyUrl: null`
    on the create response permanently; the value appears only on a later `GET`. The ticket's symptom
    is exactly "clickToApplyUrl is null", so a caller reading the create response sees no change.
  - The same instance is handed to the SNS `Create` notification —
    `CoreAPI.DataAccess/Services/PostingService.cs:131-134` → `PostingNotification.Posting` is the
    full object (`CoreAPI.Public/Domains/Posting/PostingNotification.cs:14,16-20`). **Every downstream
    consumer also gets null.**
  - Patching `posting.ClickToApplyUrl` app-side would be **wrong** — the sproc legitimately no-ops when
    `is_pending_tracking = 0`. That would invent a URL for a row that does not exist.
    ⚠️ **Corrected 2026-09-18:** this bullet originally also said "or masking is off (causes 2 and 3)".
    That half was wrong — masking-off still **creates** the row, with a NULL `tracking_url`. See
    [the corrected cause model](#the-cause-model-was-wrong--corrected-2026-09-18). Fixing it at (ii) therefore needs a re-read, and the wrap must be ordered
    *before* the SNS send — neither is scoped in the Q3 write-up.
  - **At seam (i), placing the wrap before `GetPostingAsync` makes the response and the notification
    correct for free.**

  **The original deadlock claim was correct**, and V1 confirms the premise: `AnalyticsService.cs:188-209`
  builds a raw `SqlCommand`, run by `DataAccess.ExecuteSqlCommandAsync` on its own long-lived
  `SqlConnection` with no transaction (`DataAccess.cs:17,29,64-67,78-82`). It *is* neutralised by
  `Database.ExecuteSqlRawAsync` in principle.

  **Two gaps that cannot be closed from the code:**

  - ⚠️ **Does a SQL error inside `usp_CreateWrappedUrl` doom the transaction**, so the following
    `CommitAsync` throws? Depends on the sproc's `SET XACT_ABORT` / `TRY…CATCH` and error severity.
    **This is the one live risk for seam (i), and it is GATE 2 work** — the sproc DDL is not in the repo.
  - ⚠️ **`Database.ExecuteSqlRawAsync` has no precedent in this repo.** A search for
    `ExecuteSqlRaw* / ExecuteSqlInterpolated / FromSqlRaw / FromSqlInterpolated / SqlQueryRaw` returns
    **zero hits**. The only `Database.*` calls are `CanConnectAsync`, `CreateExecutionStrategy`,
    `BeginTransactionAsync`, `EnsureCreated`, `GetDbConnection`. It is a first-of-its-kind pattern here,
    not the tidy-up the implementation note implies.

  **Confirmed on: `EnableRetryOnFailure()` is on with stock defaults** (`DependencyInjection.cs:162-166`,
  applied to the write `DataContext` at `:75-76`); repo comments put that at 6 retries / 30s backoff
  (`tests/CoreAPI.Tests.Integration/Infrastructure/CoreApiFactory.cs:307-311`, capped to 1 in the test
  harness at `:335-338`). Deadlock replay is not theoretical — `jobs` is documented in-repo as "the
  chronic deadlock victim against concurrent job writes (SqlException 1205)"
  (`CoreAPI.DataAccess/Features/JobFeatures/Common.cs:40-42`).

- ~~**OPEN QUESTION — the reporter has not been told**~~ — **CLOSED 2026-09-17 (session 3).** Comment
  `880451` on CBS-4436 covers all three: the proposed seam is unsafe, there are three causes rather
  than one, and widening the backstop breaks the PostMaster contract. Verified live 2026-09-17
  (session 4) — the phrases "seam is unsafe", "third writer" and "PostMaster contract" all match a
  `comment ~` search on the issue, while a description-only control phrase does not.
  ⚠️ The issue's `updated` field still reads `2026-09-16T19:54`, which is *earlier* than the comment.
  Unexplained; the text evidence is direct, so the comment stands as posted.

### Resolved this session — index only

| # | Question | Resolution |
| --- | --- | --- |
| Q1 | Gate on the wrap-rate query? | (c) decide direction, gate Phase 2 — **gate cleared 2026-09-18** |
| Q2 | Inline wrap vs widen backstop? | (d) inline at create, gate re-pointed to null-cause breakdown |
| Q3 | Which seam? | **(i) in-transaction, before `GetPostingAsync`** — re-decided 2026-09-18 after GATE 2 |
| Q4 | Failure semantics? | non-fatal (forced), structured alertable event |
| Q5 | Media-package children / where does the logic live? | (a) move into DataAccess, V1 delegates |
| Q6 | Per-child sproc round-trip? | (a) accept |
| Q7 | The third writer? | (b) leave out — **zero prod traffic in 200 days**; file removal separately |
| Q8 | Immediate remediation? | (a) run now, as the gate experiment |
| Q9 | ats-api bug? | split — `atsapi-v6` is unassigned, confirm ownership first |
| — | Testing | (b) unit + integration; `CoreAPI` pinned green |
| — | Process | bypass labels deliberately **not** used |

---

> After the pipeline runs, append a dated revision below — never rewrite the history above it.
> One new section per post-implementation pass. Delete this blockquote and the stub when filling the first one in.

## 2026-09-18 — revision: pipeline complete, APPROVED

**Outcome:** Planner -> Coder -> Tester -> Reviewer, two rounds. **Round 2 verdict: APPROVE.**
**377/377 tests.** Branch `feat/CBS-4436-v2-posting-analytics-wrap`, worktree
`C:\JT Repositories\CoreAPI-CBS-4436`. **Not merged, not committed** — the pipeline never merges.

**Changed by the review** (round 1 returned NEEDS WORK; both fixes applied and re-approved)

- **`XACT_STATE() = 0` is now doomed when an ambient transaction exists.** Originally treated as
  committable. Zero means no active transaction on the session, and the only caller runs inside
  `ExecuteInTransactionWithRetryAsync`'s explicit transaction — so 0 there means the transaction
  vanished. The `CurrentTransaction is not null` guard keeps the right answer for a no-transaction
  (V1) caller. Reviewer confirmed a server-side zombied transaction still leaves EF's
  `CurrentTransaction` non-null, so the guard fires exactly where intended, and that `TransactionScope`
  has **zero hits** in the repo, so that false-negative case does not exist here.
- WARNING — **a real regression was caught and fixed: V1's per-target recovery.** The first
  implementation moved V1's wrap into the shared service and lost its **per-target** try/catch, so one
  failing target abandoned the rest. That weakens `/internal/analytics/RegisterJobs` — **the
  remediation path GATE 1 used, and the one that would repair prod's 21.** Restored for V1 only via an
  exception filter (`catch (Exception ex) when (continueOnTargetFailure && ...)`), so **V2 never
  enters the catch at all** and its propagation stays byte-for-byte identical. Skipped targets now log
  an `AnalyticsWrapTargetSkipped` event with posting/job/site/recruiter ids — a silent skip there would
  have recreated this ticket's own failure class.

**Three residual deltas in V1** — inherent to Q5's relocation, accepted, recorded so they are not
later rediscovered as bugs:

- Per-target log line changed: was `"An error occurred for posting id {id}"`, now a structured
  `AnalyticsWrapTargetSkipped` event. **Behaviour identical, telemetry richer — say "restored", not
  "identical".**
- **V1's sproc-call timeout drops 90s -> 60s.** V1 used `ApplicationSettings.SqlTimeout`
  (`appsettings.json:34` = 90); the EF context uses `EntityFrameworkTimeout` (`:20` = 60). Noise for a
  few index seeks, but a real number that changed.
- Provider change `System.Data.SqlClient` -> `Microsoft.Data.SqlClient`, and V1's dedicated connection
  -> the request-scoped EF connection. Same connection string, login and database; all three call
  sites `await` in-request. No semantic change.

**N5 — resolved from existing evidence, no further write needed**

N5 asked whether the **real** sproc actually populates `tracking_url` / `wrapped_url`, or merely
creates a row — a row written with NULL `tracking_url` is **permanently unfixable**, because the
sproc's `@id is null` guard never revisits it. No test in the suite can answer this: both stubs bypass
every gate the real sproc has.

**GATE 1's own data answers it.** The 20 rows it created in UAT (`202705814`-`202705833`):
`tracking_url` null in **0**, `wrapped_url` null in **0**, `apply_url_masking = 1` on **20**, shortest
`tracking_url` 50 characters. The real sproc, under real gate conditions, populates correctly.

WARNING — **precise residual, not hand-waved:** GATE 1 invoked the sproc through V1's
`CommandType.StoredProcedure` (named parameters). The new code uses **positional**
`EXEC dbo.usp_CreateWrappedUrl @posting_id, @job_id, @hash, @image_url` via `ExecuteSqlRawAsync`. That
exact statement form has **not been executed against the real sproc**. The parameter order was
verified by reading the live DDL (GATE 2) and independently by the Reviewer, but not run. Closing it
fully needs the branch deployed to UAT, and UAT currently has **zero** cause-1 postings left to test
against.

**Reviewer flagged — still open, all non-blocking**

- **N1** `AggregateException.InnerExceptions` — only the first is walked. Less relevant now: the only
  new swallow path is unreachable by cancellation.
- **N4 / N6** — use named `EXEC` arguments, and pin the hash argument order in a test. Both are
  future-proofing; both orders verified by reading, twice.
- The `XACT_STATE() = 0`-with-transaction branch remains **untestable** in this harness — forcing it
  needs `XACT_ABORT`, which the real sproc does not set. Documented, not forged.

WARNING — **`CoreAPI.TestFramework/CoreApiTestFramework.cs` (`jtmssql` -> `localhost`) must be
EXCLUDED from any commit on this branch.** It is a documented local-setup step (repo `CLAUDE.md:33`),
byte-identical to Neru's own long-standing uncommitted change in the other worktree. Committing it
would point teammates and CI at `localhost`.

## 2026-09-18 — revision: Planner stage

**Changed**

- ⚠️ **Q5's supporting sentence is stale — the decision itself stands.** Q5 says "the doc's earlier
  idea of wrapping children as they are written required seam (i) and is dead." That was written on
  09-17 while Q3 was seam (ii). **Q3 is now seam (i), so the sentence inverts: wrapping children as
  they are written is exactly what happens.** Q5's *decision* — (a), a DataAccess service that V1
  delegates to, wrapping parent **plus** media-package children — is met in full and is unchanged.
  - **This is the third piece of downstream reasoning the Q3 re-decision invalidated** (after Q4's
    "forced" non-fatal, and the cause-3 no-op claim in the GATE 2 write-up). The pattern is worth
    naming: **reversing Q3 silently voided arguments elsewhere in the doc that were premised on it.**
    Each was caught by re-reading rather than by any check. Worth a sweep before the next reversal.
- The wrap lands in `WriteSinglePostingCore`, between `SaveChangesAsync` and `GetPostingAsync`. Both
  boundaries are load-bearing: before the flush the `jobs_sites` row is not visible to the sproc, so
  `@site_id` is NULL and it silently no-ops; after `GetPostingAsync` the response and SNS payload are
  already null. A once-per-bundle wrap is impossible — at parent-wrap time the children do not exist.

**Reviewer flagged**

Three judgement calls the Planner recorded for the Reviewer; none blocks the run:

- **J1** — `img_url` stays hardcoded to `https://www.click2apply.net/`, matching V1 and the sproc in
  all three environments. Config-sourcing it would change V1 behaviour in UAT/QA. The API response is
  unaffected: `SetApplyUrls` composes that from config + hash, as GATE 1 observed live.
- **J2** — wrap runs once per posting, not once per bundle. See the Q5 note above.
- **J3** — the three V1 call sites are left untouched; delegation happens inside
  `CreateWrappedUrlsForPostingAsync`, whose signature does not change. Q5's "touches three V1 call
  sites" was a cost estimate, not a requirement; this is a strictly smaller diff.

**Also surfaced by the Planner** (verified independently before recording):

- `CoreAPI.DataAccess.Services.IAnalyticsService` **already exists** as an HTTP wrapper over the
  external analytics API. The new service must be `IAnalyticsWrapService` to avoid a collision.
- **The pinned suite is a free canary.** `CoreAPI.Test` builds its schema with `EnsureCreated()`
  (`CoreAPI.TestFramework/CoreApiTestFramework.cs:183`) — **tables only, no stored procedures**, and
  nothing in `CoreAPI.Test` deploys any. So `usp_CreateWrappedUrl` does not exist there, every create
  raises SQL error 2812 (statement-level, committable), and it **must** be swallowed. A blanket-fail
  or mis-scoped catch turns the existing posting tests red immediately. **A result below 367/367 means
  the wrap is wrong, not the test.**
- The doomed-transaction rethrow is **not reachable** in that harness, and
  `Microsoft.Data.SqlClient.SqlException` has no public constructor, so the 1205 / severity branches
  cannot be unit-tested either. The classification lives in one named method and the untestable
  branches are to be **reported as a gap, not faked**.
- `jf.value1` holds the parent **posting** id despite the parameter being named `parentSiteId`
  (`PostingCreateCommands.cs:246`, stored at 580-582). Matches V1's UNION. **Do not "fix" it.**
- Only two `jobs_sites` writers exist — `PostingCreateCommands` and `OrderCommands` (Q7, out of
  scope). `PostingPatchCommands` creates no posting rows. No fourth writer was missed.

**New open questions**

- None.
