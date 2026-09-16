---
type: design-doc
ticket: CBS-4436
team: CBS
status: in progress
repos:
  - CoreAPI
grilled: 2026-09-17
updated: 2026-09-17
---

# CBS-4436 — V2 posting analytics wrap

- **Status:** in progress — ⚠️ **Phase 1 incomplete.** Grilling paused at Q1, nothing decided yet.
- **Ticket:** [[tickets/CBS-4436.md]] — *Discovery: analytics click-to-apply hash missing for postings created via core-api V2 create path — decide whether to add inline wrap*
- **Jira:** CBS-4436 · Investigation · High · Selected for Development · reporter Shervin Ivari · assignee me
- **Grilled:** 2026-09-17 via /grilling — **paused, resume at Q1 below**
- **Last touched:** 2026-09-17

> **Resume here:** every decision below is still open. Q1 is on the table awaiting my answer;
> Q2–Q9 are mapped but unasked. The "Verified facts" section is done and does not need redoing —
> it was read out of the repo at `fcf24ca5`, not guessed.

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

**Repo commands** — from the repo's own tracked `CLAUDE.md` (repo wins over vault defaults):
`dotnet test`, filter with `dotnet test --filter "FullyQualifiedName~X"`. Integration tests need a
local MSSQL container (`mcr.microsoft.com/mssql/server:2019-latest`, port 1433). **Not yet run —
so not yet pinned in [[protocols/coding-standards.md]].**

## Decisions

- **None yet.** Phase 1 paused before Q1 was answered. Nothing here is settled; do not let a
  Planner read this section as a spec.

## Rejected

- **Nothing rejected yet.** Options are enumerated under Q2/Q3 below, all still live.

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

The decision tree as mapped. **Q1 was asked and is awaiting my answer. Q2–Q9 are mapped but not
yet put to me.** Recommendations are the agent's, not my decisions.

- **OPEN QUESTION — Q1 (asked, unanswered): gate the decision on the wrap-rate query, or decide on
  existing evidence?** The ticket makes discovery question 1 the deciding input; it is currently
  unobtainable. Options: **(a)** decide now, note the query as unrun *(agent's rec)*; **(b)** block
  Phase 1 until MSSQL access is restored; **(c)** decide direction now, make the query a required
  check before Phase 2 ships.
  - Agent's argument for (a): the rate changes urgency, not direction — 13+22 postings that missed
    every backstop is existence proof of a permanent-null path, and a rate cannot refute it.
  - Honest counter it conceded: if the rate came back ~100% for those channels, that would argue the
    13 were a one-off window and push toward "widen the backstop" over "change the create path."
    So the query **cannot flip whether to fix, but could flip where.**

- **OPEN QUESTION — Q2: inline wrap at V2 create, vs widen an existing backstop, vs both?**
  Widening = drop the `campaign_posting` inner join from `PM.usp_get_jobs_applyurl_not_wrapped` so
  the sweep covers non-campaign postings. The two are not exclusive, and they have different blast
  radii: the sweep change is one sproc and affects every channel at once; the inline change is
  scoped to core-api but leaves the other unwrapped writers alone.

- **OPEN QUESTION — Q3: if inline — which seam?** Two candidates, and the transaction facts above
  make this load-bearing, not cosmetic:
  - **(i)** inside `PostingCreateCommands` (`WriteSinglePosting`/`WriteBundlePostings`), as the
    ticket proposes — in-transaction, replayed on retry, and requires plumbing the salt into an
    `internal static` class.
  - **(ii)** in `PostingService.CreatePostingAsync` **after** `PostingCreateCommands` returns —
    out-of-transaction, once only, salt already in scope, and it **mirrors V1's actual shape**
    (after the write, non-fatal, logged). It would sit right next to the existing SNS notification,
    which is already a post-commit side effect on that exact seam.
  - Worth grilling: (ii) looks strictly better on every constraint found so far. Is there a reason
    the ticket proposed (i) that I know and the code does not show?

- **OPEN QUESTION — Q4: failure semantics.** V1 is non-fatal — logs and swallows, posting still
  returns 200. Does V2 match that, or should a failed wrap fail the create? (Matching V1 keeps the
  backstops meaningful; failing hard makes the gap loud but can reject a posting that is otherwise
  fine.)

- **OPEN QUESTION — Q5: media-package children.** V1 wraps the full target set via the UNION query.
  Does V2 do the same, or only the posting itself? Note `WriteBundlePostings` already iterates
  children in-process — V2 may be able to wrap each child as it is written and skip the UNION query
  entirely, which would be cheaper than V1.

- **OPEN QUESTION — Q6: unconditional wrap at create — any downside?** The ticket argues no:
  `usp_CreateWrappedUrl` is idempotent (`@id IS NULL` guard) and self-gates on
  `p_sites.is_pending_tracking`, so non-tracking sites are correct no-ops. **Unverified by me** —
  the sproc DDL was not read this session (MSSQL down; DataGrip cache not checked yet). Perf on
  bundle creates is the open part: one sproc round-trip per child posting.

- **OPEN QUESTION — Q7: the third writer.** Does `OrderCommands.AddOrderItemAsync` /
  `POST /api/experiments/job/{jobId}/order` get wrapped too, get left alone, or get its own ticket?
  Depends on whether it sees prod traffic — currently unknowable.

- **OPEN QUESTION — Q8: immediate remediation.** Run `/internal/analytics/RegisterJobs` for the
  affected posting IDs now, or fold it into the Phase 2 ship? The ticket says it is independent and
  idempotent.

- **OPEN QUESTION — Q9: the ats-api secondary bug.** ats-api's fire-and-forget raw `Thread` wrap
  dies on `ThreadAbortException`. Ticket asks: include here or split? Different repo, different
  failure mode — splitting looks right, but it is my call.

- **OPEN QUESTION — testing.** A raw sproc call is awkward to unit test.
  `PostingCreateCommands_Tests.cs` exists as a seam, and the repo has an integration-test path that
  needs a local MSSQL container. Pin the real `dotnet test` command by running it before any
  pipeline run here — no `CoreAPI` row exists yet in [[protocols/coding-standards.md]].

- **OPEN QUESTION — process.** Jira labels on this ticket include `MR_bypass`, `UAT_Bypass` and
  `noqarequired`. Not acted on, not interpreted. Flagging that they are set.

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
