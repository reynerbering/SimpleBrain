---
type: design-doc
ticket: CBS-4436
team: CBS
status: decided
repos:
  - CoreAPI
grilled: 2026-09-17
updated: 2026-09-17
---

# CBS-4436 — V2 posting analytics wrap

- **Status:** in progress — ⚠️ **Phase 1 COMPLETE.** Q1–Q9 + testing + process all decided.
- **Ticket:** [[tickets/CBS-4436.md]] — *Discovery: analytics click-to-apply hash missing for postings created via core-api V2 create path — decide whether to add inline wrap*
- **Jira:** CBS-4436 · Investigation · High · Selected for Development · reporter Shervin Ivari · assignee me
- **Grilled:** 2026-09-17 via /grilling — **complete**
- **Last touched:** 2026-09-17

> **Phase 1 complete (2026-09-17).** Every question below is decided — see Decisions. Two gates must
> clear before Phase 2 ships: the `RegisterJobs` flip-count experiment (Q8) and a live re-read of the
> sproc DDL (the copy below is a 2026-07-08 cache snapshot). The "Verified facts" and "Sproc facts"
> sections are done and do not need redoing — read out of the repo at `fcf24ca5` and the
> DataGrip prod cache, not guessed.

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
- **Q3 — decided 2026-09-17: (ii) post-commit in `PostingService.CreatePostingAsync`.** Not (i).
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

Read 2026-09-17 from the **DataGrip prod cache, snapshot 2026-07-08** — *not a live read*.
`usp_CreateWrappedUrl` carries a `20260527` change, so the snapshot post-dates it; anything shipped
after 2026-07-08 is not reflected. MSSQL MCP was down. Re-verify live before Phase 2.

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

- **OPEN QUESTION — GATE 1: the `RegisterJobs` flip-count experiment has not been run.**
  Blocked on credentials, not access — core-api requires `X-API-KEY`; Neru runs it, the key stays in
  his environment. Runner: `cbs4436-experiment.ps1` (read-only by default, prod write under
  `-Execute`). **This can invalidate the entire direction:** if most of the 35 postings stay null,
  the ticket's root cause is wrong and Q2 must be reopened before any implementation.

- **OPEN QUESTION — GATE 2: both sprocs were read from a 2026-07-08 DataGrip cache snapshot, not
  live.** `usp_CreateWrappedUrl` and `PM.usp_get_jobs_applyurl_not_wrapped` must be re-read against
  prod `64recs67o` before Phase 2 ships. MSSQL MCP was down all of 2026-09-17. Everything in
  "Sproc facts" — including the three-causes finding that drove Q2 — rests on that snapshot.

- **OPEN QUESTION — does Q3 deserve a second look?** Q3 chose seam (ii) partly on the argument that
  a raw `SqlCommand` inside `ExecuteInTransactionWithRetryAsync` sits on its own connection and
  self-deadlocks. Using `Database.ExecuteSqlRawAsync` instead puts the call on the context's **own**
  connection and transaction, so that specific deadlock does not arise and **seam (i) is more viable
  than the Q3 write-up claims**. (ii) still looks right on the surviving arguments — retry replay,
  transaction lock-hold time on hot tables, and Q4's non-fatal contract only being coherent
  post-commit. **Raised with Neru 2026-09-17; not yet answered.**

- **OPEN QUESTION — the reporter has not been told** that the ticket's proposed seam is unsafe, that
  there are three causes rather than one, or about the third writer. Worth a comment on CBS-4436
  before Phase 2 starts, so the design is not a surprise at review.

### Resolved this session — index only

| # | Question | Resolution |
| --- | --- | --- |
| Q1 | Gate on the wrap-rate query? | (c) decide direction, gate Phase 2 |
| Q2 | Inline wrap vs widen backstop? | (d) inline at create, gate re-pointed to null-cause breakdown |
| Q3 | Which seam? | (ii) post-commit in `PostingService` — *but see the open re-look above* |
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

## YYYY-MM-DD — post-implementation revision

**Changed**
- <decision> revised to <new> — because <what the build revealed>.

**Reviewer flagged**
-

**New open questions**
-
