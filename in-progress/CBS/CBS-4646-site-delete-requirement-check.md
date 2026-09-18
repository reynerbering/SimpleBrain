---
type: design-doc
ticket: CBS-4646
team: CBS
status: in progress
repos:
  - CoreAPI
grilled: 2026-09-18
updated: 2026-09-18
---

# CBS-4646 — Site delete requirement and product duration check on stop

- **Status:** in progress — **D2 and D8 are reopened.** Prod verification on 2026-09-18 tripped D8's own gate: the `requires_pending_delete` setting is far too sparse for "absent = not required" to be safe. D1, D3–D7 and D9–D12 stand. Do not start Phase 2. See [the prod-verification revision](#2026-09-18--revision-prod-verification).
- **Ticket:** [[CBS-4646]]
- **Jira:** [CBS-4646](https://jobtarget.atlassian.net/browse/CBS-4646) — Story, Backlog, High, unassigned, label `CBSWk38of2026`, reporter Shiela Mojeno. Verified via Atlassian MCP 2026-09-17.
- **Grilled:** 2026-09-18 via `/grilling`
- **Last touched:** 2026-09-18

## Problem

- Core V2's stop-posting flow writes `pending_delete` / `pending_automated_delete` for **every** posting it stops, regardless of whether the site actually needs a close request sent to the board.
- That queues pointless work in DES, and for SEEK it burns a credit — the posting gets closed early instead of running its full paid duration.
- The rule already exists on the DB side: **DBA-2636** shipped it for `usp_oneclick_delete_nonintegrated_posting` and is **Deployed to Production**. Core V2 never got it.
- My own comment on the ticket, 2026-09-16: *"This is ready to implement, we don't have this mechanism in Core V2."*
- CBS-4646 **blocks [PJO-11160](https://jobtarget.atlassian.net/browse/PJO-11160)** — "Update SEEK Integration to Allow Natural 30-Day Expiration — Site ID 25461 (Phase 1)", Resolved. PJO-11160 is where the *duration* half of this ticket comes from, and it is far more specific than CBS-4646's own description:
  - postings that complete their full product duration → **move directly to Expired**, do not enter Pending Delete, **no `closePostedPositionProfile` sent**;
  - early stop → Pending Delete, close request still sent.

**Volume** — Shiela, 2026-09-08. 43 postings currently in a delete status on sites that do not require deletion. Started ~Sept 2024.

| site_id | site_name | total | pending_delete | pending_automated_delete |
| --- | --- | --- | --- | --- |
| 25393 | JobTarget Programmatic | 25 | 25 | 0 |
| 17466 | CompliancePost Veteran and Disability (OFCCP) | 10 | 10 | 0 |
| 5258 | WorkForce West Virginia | 2 | 2 | 0 |
| 4416 | EmployOklahoma | 1 | 0 | 1 |
| 15012 | Indeed | 1 | 1 | 0 |
| 20868 | Hire Patriots | 1 | 1 | 0 |
| 5264 | Hire Wyoming | 1 | 1 | 0 |
| 26325 | CounselorJob.com | 1 | 1 | 0 |
| 23306 | Colorado State University - College of Business | 1 | 0 | 1 |

## The rule

Collapses to one sentence: **`pending_delete` is written only when the site requires deletion *and* the posting is ending early. Everything else expires.**

| `requires_pending_delete = 1`? | duration reached? | outcome |
| --- | --- | --- |
| no | — | `expired` (process `expire-no-delete-required`) |
| yes | yes | `expired` (process `expire-duration-reached`) |
| yes | no | `pending_delete` / `pending_automated_delete` — unchanged |

CBS-4646's description only defines the bottom two rows. The top row is the one that explains all 43 stuck postings, and it came from DBA-2636's wording, not from this ticket.

> ⚠️ **The first row of this matrix is reopened as of 2026-09-18.** Prod data shows `requires_pending_delete` is set on only 113 sites, so "no" is not a discriminator — it is a near-universal default that would suppress 99.3% of Core V2's close requests. Row 1 must be re-decided before this table is built. Rows 2 and 3 are unaffected. See [the prod-verification revision](#2026-09-18--revision-prod-verification).

## Where the code actually is

Read on 2026-09-17 against `CBS-4643-ofccp-getjobs-param-validation` @ `fcf24ca5`.

- **V2 `DELETE /api/v2/posting/{postingId}`** → `PostingService.StopPostingAsync` → `PostingDeactivationCommands.StopPostingAsync`. The only stop flow that lives in C#.
- **V1 is all stored procs** — `DELETE /api/job/{jobId}` → `usp_oneclick_job_stop`; `StopJobPosting` / `StopJobParentAndChildrenPostings` → `usp_oneclick_posting_stop`. V2 `JobController` has **no** stop/delete endpoint at all.
- `job_distribution_transmit_site` has an EF entity. **`job_distribution_transmit_site_setting` does not** — no entity, no DbSet, no mapping. This is the only genuinely new data access.
- Product duration is already materialised into `jobs_sites.expire` at create: `SetProductExpiry` → `ResolveExpiryDays(isMediaPackageSite, isProgrammatic, product.Duration ?? 30)` → `SetExpirationDate(start, days)`, landing on **23:59:59 local** on the last day.

**Five places write a delete status in C#** — not one:

| # | Location | Path | Writes |
| --- | --- | --- | --- |
| 1 | `PostingDeactivationCommands.cs:164` | parent, always `MoveAction.Delete` | `pending_automated_delete` or `pending_delete` |
| 2 | `Common.cs:205` | child, `Expire`, cloud | `pending_delete` |
| 3 | `Common.cs:211` | child, `Expire`, non-cloud | `pending_delete` + `ExpireJobSite` |
| 4 | `Common.cs:226` | child, `Delete`, CloudPlus | `pending_delete` |
| 5 | `Common.cs:263` | child, `Delete`, else | `pending_automated_delete` or `pending_delete` |

### What the cached proc DDL shows

Read 2026-09-18 from the DataGrip offline cache (see [[protocols/repo-memory.md]] and the memory `datagrip-cached-ddl-offline-fallback`), **snapshot dated 2026-07-08** — not a live read.

- **`usp_oneclick_posting_stop`** — 612 lines. **No** `requires_pending_delete`, **no** `transmit_site_setting`, **no** duration logic. 20 mentions of `pending_delete`, 1 of `pending_automated_delete`. The mechanism genuinely is not there.
- **`usp_oneclick_job_stop`** — 297 lines. Writes **no** `jobs_sites_status` rows at all and contains **zero** `pending_delete` references. It updates `jobs` and `jobs_sites` directly and calls `usp_oneclick_posting_distribution_update` 8×. It does **not** call `usp_oneclick_posting_stop`.
  - So the "**job** process" half of the ticket title is loose wording: the job stop does not route through the delete-status machinery at all. Whatever the V1 follow-up turns out to be, it is not simply "add the same check to job_stop".
- **`usp_oneclick_delete_nonintegrated_posting`** — 319 lines, **0** mentions of `requires_pending_delete`.

⚠️ **That last one calibrates how far to trust this cache.** DBA-2636 is *Deployed to Production* and its whole change was adding `requires_pending_delete` to exactly that proc — so the cached copy is provably behind prod. Treat every finding above as "true as of 2026-07-08", and re-confirm against a live connection before acting on the V1 follow-up. It is good enough to have settled D1, which is a scope decision, not a code change.

**Useful trick, reusable:** to calibrate the cache's staleness, read a proc you *know* changed recently and check whether the change is present. That is what the nonintegrated proc was used for here.

## Decisions

- **D1 — Scope to V2 `StopPostingAsync` only.** It is the one flow that is C#; the V1/proc paths are DBA-owned. The decision stands unchanged after reading the actual proc DDL (see below) — which **confirms** the premise rather than assuming it: neither stop proc has the mechanism today. The V1 gap is named below in Scope, not silently left out.
- ⚠️ **D2 — REOPENED 2026-09-18, do not implement.** Prod data refuted the premise; see [the prod-verification revision](#2026-09-18--revision-prod-verification). Original reasoning kept below as the record. — **Site does not require deletion → expire immediately.** CBS-4646 never defines this branch; DBA-2636 says "skipped and NOT moved". *Skip* is safe wording in a nightly cleanup proc but wrong in a **stop** flow: the caller asked for the posting to stop, so leaving the status untouched ends with `IsStopped = true, Show = false` and a status still reading `pending`, which `PostingQueries` maps as live. One terminal state, no fourth posting shape.
- **D3 — "Duration reached" reads `jobs_sites.expire`, not `p_products.duration`.** `expire` *is* the product duration, materialised at create, and it is already on the loaded entity — zero extra queries. Two rules travel with this:
  - `Expire` is `DateTime?`. **Null → treat as not reached → `pending_delete`.** The safe side: we still tell the board to close.
  - PATCH/PUT posting can overwrite `expire`. An operator who shortened a posting genuinely *has* shortened its duration, so honouring it is correct. "Product duration" in the ticket therefore means **the posting's effective expiry**.
- **D4 — Compare in EST, inclusive: `expire <= EstNow()`.** Matches the clock the value was written in. `DateTime.UtcNow` runs 4–5 hours ahead, which would declare a posting duration-reached up to 5 hours early and skip a close request on a posting with paid duration left — the mirror image of the bug PJO-11160 exists to fix. Inclusive because `expire` lands on 23:59:59, not midnight.
- **D5 — Gate all five write sites, through one shared decision on `PostingUpdate`.** Add `RequiresPendingDelete` and `DurationReached` alongside the existing `Cloud` / `CloudPlus` / `AutoDeleteSwitch` switches; compute in `UpdateParentStatusIfNotTerminal` and `BuildChildUpdate`. The setting is keyed on `site_id` and media-package children each carry their **own** `child.Site` — so it must be computed per posting. Deciding once for the parent and inheriting down would be wrong.
- **D6 — The bypass branch reuses the existing php-integration shape and suppresses the outbound delete.** Gating the status alone is not enough: the close request is queued at **`Common.cs:238`** (`AddJobExternalTransmit(child, "delete", …)`) which runs *before* the status decision at `:263`. Status-only gating would send the posting to `expired` and still tell the board to delete it — exactly what PJO-11160 forbids. The shape already in the file at `Common.cs:254-260` is the model: `UpdateJobSiteStatus("expired")` + `ExpireJobSite` + `RemoveJobFlags` + suppressed delete transmit.
  - **Distinct `process` strings** — `expire-duration-reached` and `expire-no-delete-required`. PJO-11160's last AC is *"Logging clearly identifies whether a posting ended through natural expiration or an early close request."* Today every row says `delete` or `expire_cloud`. `createdBy` unchanged.
  - **The parent path has no `AddJobExternalTransmit`** — `UpdateJobExternalTransmit` only deactivates. For the parent the `pending_delete` status row *is* the DES signal, matching DBA-2636's framing. Transmit suppression only bites on the child delete path.
- **D7 — New entity + one batched lookup, not a navigation Include.** `LoadChildPostings` includes `Site.JobDistributionTransmits` **only when `!onlyExpireIncludes`** (`:242-249`) — and D5 gates the Expire path, which is exactly the `onlyExpireIncludes = true` case. A navigation read would force that conditional open and undo the narrowing its XML docs were written to justify. Instead: collect distinct site IDs across parent + children, one query, return a `HashSet<int>`.
  - `value` mapped as **`string`**, compared `== "1"`. Every other `name`/`value` pair in this schema is a string (`JobExternalTransmitLoginEntity.Value`, `RecruiterSiteLoginDetailEntity.Value`). The ticket's SQL writes `tss.value = 1` unquoted, which SQL Server resolves by implicit conversion and EF will not. **Assumption, not verified** — see Open questions.
  - `WithHint(TableHint.Nolock)`, matching the ticket's `WITH(NOLOCK)` and the existing idiom at `JobFeatures/Common.cs:44`.
- ⚠️ **D8 — REOPENED 2026-09-18, its own gate failed.** The verification this decision made conditional was run and came back negative; see [the prod-verification revision](#2026-09-18--revision-prod-verification). Original reasoning kept below as the record. — **Data-driven for all sites, no feature flag, conditional on a prod verification gate.** The failure modes are **not symmetric**:
  - sending an unneeded delete → DES noise. Today's state, and what Shiela filed.
  - **not** sending a needed delete → the posting stays live on the board after the client stopped it. Customer-visible, and on credit-based boards, billable.

  This change moves behaviour toward the second one, so "no `requires_pending_delete = 1` row" has to genuinely mean "does not need a close request", not "nobody configured it yet". DBA-2636 already shipped those semantics to prod — but for *non-integrated* sites, a different population from the cloud/OneClick sites these flows cover. Hence the gate rather than blind trust. There is no feature-flag infrastructure in CoreAPI (no `IFeatureManager`, no LaunchDarkly, nothing in `appsettings.json`), so a flag would mean building one.
- **D9 — Test at both layers.** The core is a pure function `(requiresPendingDelete, durationReached) → outcome` — unit-test it directly off an `internal static` helper, same shape as `ResolveExpiryDays`. Plus DB-backed cases in `CoreAPI.Test/Client_Tests/Posting_Tests/StopPosting_Tests.cs` proving the status row **and** the suppressed transmit row for at least one child-delete case. The side effect at `Common.cs:238` is where this breaks, and a unit test cannot see it.
- **D10 — Backfill of the 43 existing rows is out of scope, and we raise nothing for it.** Neru: *"let them deal with that."* Fixes forward only; existing `pending_delete` rows untouched. Recorded here as a scope boundary so a later reader knows it was decided, not overlooked.
- **D11 — Accept the response/SNS status change; envelope unchanged, no versioning.** `PostingService.StopPostingAsync` (`:81-87`) publishes `PostingNotification(PostingNotificationAction.Delete, posting)` on every successful stop. Bypassed stops now report `Expired` instead of `PendingDelete` in both the HTTP body and the SNS message. Not a schema change — `Expired` is already returnable today via the php-integration branch at `Common.cs:256`, so consumers switching on status already handle it. `PostingNotificationAction.Delete` describes the *action*, not the status, and stays. Worth a heads-up to the downstream topic owners about the distribution shift; not a code change here.
- **D12 — Green baseline required before `/ship`.** Fix the container (`ALTER TABLE [64recs67o].dbo.jobs_info_long ADD site_id INT NULL;`), confirm 383/383, then start Phase 2. "No regression on existing flows" is the ticket's own AC and is unverifiable against a red suite — and a genuine new failure would hide inside the 57 existing `"Job creation failed."` results. **Phase 2 branches from current `develop`** (contains `ee28457e`, the .NET 10 upgrade), not from the pre-upgrade commit this grilling read.

## Rejected

- **Modifying `usp_oneclick_posting_stop` / `usp_oneclick_job_stop` as part of this ticket** — covers every caller, but puts Core on the hook for DBA-owned procs we have no DDL for. The only local copy is a 46-line test stub.
- **A Core-side gate in `JobService` before the V1 proc calls** — cheap, but splits one rule across two layers with no single place to read it.
- **Literal DBA-2636 "skip"** (no status row written, only `MarkParentAsStopped`) — faithful to the sibling ticket, but invents a fourth posting state that every downstream reader has to learn.
- **Recomputing `start + p_products.duration`** — needs `jobs_sites → r_orders_items_links (type='job') → r_orders_items.product_id → p_products.duration`, the 348M-row links table that `IsChildPostingAsync` and `LoadParentPosting` were explicitly rewritten to avoid. It would also have to re-implement `ResolveExpiryDays` — genuine media-package sites use a fixed 60 days, **not** the product duration, with 25393 carved out (CBS-4162). It would disagree with the stored expire for exactly the site topping Shiela's list.
- **Date-only comparison** (`expire.Date < EstNow().Date`) — immune to clock skew but shifts the boundary by up to a full day and silently changes same-day stops.
- **Gating the Delete path only (writes 1, 4, 5)** — leaves `Common.cs:205`/`:211` writing `pending_delete` on the Expire path. Same bug, same table. Note site 25393 is hard-coded `false` in `IsProgrammatic` (`Common.cs:22`) and excluded in `IsMediaPackageAsync`, so it is treated as a single posting and hits write 1 — parent-only gating probably does clear Shiela's biggest line, but leaves the other eight sites' children on the old behaviour.
- **`ThenInclude` off the existing `JobDistributionTransmits`** — more EF-idiomatic, but re-widens both load paths and adds a fourth collection to a deliberately trimmed `AsSplitQuery` graph.
- **`FromSqlRaw` with the ticket's query verbatim** — no entity to maintain, but cuts against the EF-native direction of the rewrite and needs extra plumbing against the integration-test schema.
- **appsettings kill-switch** — ~10 lines, but CoreAPI ships by redeploy anyway, so it buys less than it looks like.
- **Site allowlist (25461 + Shiela's nine)** — safest, but it does not fix the ticket. It fixes ten sites, leaves the general rule unbuilt, and becomes permanent config nobody prunes.
- **Reporting `PendingDelete` while writing `expired`** — lying about stored state is worse than the change.
- **A new response field for the exit reason** — useful for PJO-11160's logging AC, but an API surface addition beyond this ticket. The `process` strings make it recoverable from the data.
- **Accepting the 84 known-red tests as a baseline and comparing counts** — makes the Tester reason about a failure set instead of a boolean.

## Scope

**In**

- V2 `PostingDeactivationCommands.StopPostingAsync` — parent and media-package children.
- All five delete-status write sites (table above).
- New `JobDistributionTransmitSiteSettingEntity` + DbSet + one batched lookup.
- `RequiresPendingDelete` / `DurationReached` on `PostingUpdate`.
- Suppressing `AddJobExternalTransmit(…, "delete")` on the bypass path.
- Unit tests for the matrix + DB-backed tests in `StopPosting_Tests`.

**Out**

- **V1 / stored-proc stop flows** — `usp_oneclick_posting_stop`, `usp_oneclick_job_stop`. Core V2 has no job-level stop at all, so the "job process" half of the ticket title cannot be done in this repo. Needs a DBA sibling ticket; **not raised yet.**
- **Backfill of the 43 existing rows** (D10) — reporter's side, nothing raised by us.
- **The UTC/EST inconsistency inside `Common.cs`** — `ExpireJobSite` and `MarkParentAsStopped` write UTC while `UpdateJobSiteStatus` stamps EST, on the same stop. Pre-existing, deserves its own ticket, fixing it here would widen the blast radius past "no regression".
- Feature flags, allowlists, API surface additions.

## Open questions

Three of the four were **answered against prod on 2026-09-18** — full results and consequences in
[the prod-verification revision](#2026-09-18--revision-prod-verification). Summarised here so this
section stays readable at a glance:

- ✅ ~~**What exact type and length is `job_distribution_transmit_site_setting.value`?**~~ — **ANSWERED 2026-09-18, prod.** `varchar(500) NOT NULL`. `name` is `varchar(25) NOT NULL`. **D7 is correct as written**: map as `string`, compare `== "1"`.
- ✅ ~~**Is `requires_pending_delete = 1` actually populated for the integrated sites that need close requests?**~~ — **ANSWERED 2026-09-18, prod. NO — and this trips D8's gate.** Only **12 of 6,217** strict-`IsCloud` sites carry the flag. Of Core V2's own 173,776 delete-status writes in the last 30 days, **99.3% (172,545) land on unflagged sites**. **D2 and D8 must be re-decided before any implementation.**
- OPEN QUESTION: **Does the seeded `coreapi-test-sql` container have `job_distribution_transmit_site_setting`?** Still open — not checked, and moot until D2/D8 are resolved. If missing, the fix is an entry in `CoreAPI.Test/Scripts/000_schema_drift.sql` (see the pre-implementation revision), not the other suite's schema scripts.
- ✅ ~~**Which of the five write paths does each of Shiela's nine sites actually take?**~~ — **ANSWERED 2026-09-18, prod.** All nine have **no setting row at all** — not even an explicit `'0'`. Feature breakdown is in the revision. This is the finding that exposes the semantics problem: the rule cannot tell Shiela's 9 sites apart from the other 745 Core V2 stops postings on.

### How to close them

All four are answerable in one session against a working MSSQL connection plus a running container. Do that before Phase 2.

**Attempted 2026-09-18, could not run.** All three `*-64recs-mssql` MCP servers were `CONNECT_TIMEOUT` at 30s — as were `jira`, `gitlab`, `datadog` and all three Postgres servers, while the cloud-routed Atlassian connector worked fine. That split points at the VPN, not the database hosts. **The MCP servers only attempt connection at session startup**, so reconnect the VPN *then* start a new session — retrying inside a running one does nothing.

**The DataGrip offline cache partially helps — know which half.** Memory `datagrip-cached-ddl-offline-fallback` has the path and method; the working zips are under
`~/DataGripProjects/Databases/.idea/dataSources/372ba93c-7d52-4171-beed-9b4f48ef1f1c/storage_v2/_src_/database/64recs67o.jZC0oA/schema/dbo.sYMBAA.zip`
(4107 entries, read with Python `zipfile` — `unzip -j` fails on the leading-slash entry names).

- ✅ **Routine DDL is there in full** — that is how the proc findings above were obtained.
- ❌ **Per-column table DDL is not**, exactly as the memory warns. There is no `/table/` entry for `job_distribution_transmit_site_setting`, so **OQ1 cannot be closed offline**.
- ❌ The *other* DataGrip cache at `%LOCALAPPDATA%/JetBrains/DataGrip2024.2/data-source/7d830600/…/entities/entities.dat.values` holds only a fragment of a default-constraint name. Dead end, don't retry it.

**Partial answer to OQ1 already in hand.** `usp_job_distribution_transmit_site_settings_get` (AGL-6841, 2021-08-11) `PIVOT`s `MAX([value])` from that very table into `[server]`, `[port]`, `[username]`, `[password]`, `[destination]`, `[file_type]`. A single column pivoted into both `password` and `port` can only be character data — so **`value` is a string, and D7's `== "1"` comparison is very likely right**. OQ1 stays open only for the exact type and length (`varchar` vs `nvarchar`, `max_length`), which the EF mapping needs.

Column names below for `p_sites` / `p_sites_features` are from the EF mappings (`PartnerSiteEntity`, `PartnerSiteFeatureEntity`), read on 2026-09-18 — not guessed. The `job_distribution_transmit_site*` names come from the SQL in CBS-4646 and DBA-2636, which is exactly what OQ1 exists to confirm.

**OQ1 — the `value` column type.** The one that can silently invert the whole gate.

```sql
SELECT c.name AS column_name, t.name AS data_type, c.max_length, c.is_nullable
FROM [64recs67o].sys.columns c
JOIN [64recs67o].sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('[64recs67o].dbo.job_distribution_transmit_site_setting')
ORDER BY c.column_id;
```

**OQ2a — what values exist, and on how many sites.**

```sql
SELECT tss.value, COUNT(DISTINCT ts.site_id) AS site_count
FROM [64recs67o].dbo.job_distribution_transmit_site ts WITH(NOLOCK)
JOIN [64recs67o].dbo.job_distribution_transmit_site_setting tss WITH(NOLOCK)
  ON tss.transmit_site_id = ts.transmit_site_id
WHERE ts.active = 1 AND tss.active = 1 AND tss.name = 'requires_pending_delete'
GROUP BY tss.value;
```

**OQ2b — the risky cross-check: integrated sites *without* the flag.** A large `unflagged` is the result that stops the design — it would mean we quietly cease sending close requests to integrated boards.

> ⚠️ **The CTE version below was rejected by the MCP tool** ("Only SELECT queries are allowed") and its `IsCloud` definition is loose. Kept for the record. **Use the verified-working versions in [Queries as actually run](#queries-as-actually-run).**

```sql
WITH flagged AS (
    SELECT DISTINCT ts.site_id
    FROM [64recs67o].dbo.job_distribution_transmit_site ts WITH(NOLOCK)
    JOIN [64recs67o].dbo.job_distribution_transmit_site_setting tss WITH(NOLOCK)
      ON tss.transmit_site_id = ts.transmit_site_id
    WHERE ts.active = 1 AND tss.active = 1
      AND tss.name = 'requires_pending_delete' AND tss.value = 1
),
cloud AS (
    SELECT DISTINCT f.site_id
    FROM [64recs67o].dbo.p_sites_features f WITH(NOLOCK)
    WHERE f.active = 1 AND f.enabled = 1
      AND f.feature = 'oneclick_integration_pipeline'
)
SELECT
    (SELECT COUNT(*) FROM cloud)                                             AS cloud_sites,
    (SELECT COUNT(*) FROM cloud c JOIN flagged fl ON fl.site_id = c.site_id) AS flagged,
    (SELECT COUNT(*) FROM cloud c LEFT JOIN flagged fl ON fl.site_id = c.site_id
      WHERE fl.site_id IS NULL)                                              AS unflagged;
```

**OQ3 — against the container, not prod.** `docker start coreapi-test-sql` first. Non-null means the entity will translate and D9's DB-backed tests can run.

```sql
SELECT OBJECT_ID('[64recs67o].dbo.job_distribution_transmit_site_setting');
```

**OQ4 — branch drivers for Shiela's nine sites.** `pipeline + ext_posting + NOT php` = `IsCloud`; `programmatic` and `site_type_id_jt` feed `GetMoveAction`. Between them they place each site on one of the five write paths.

```sql
SELECT s.site_id, s.site_name, s.site_type_id_jt,
       MAX(CASE WHEN f.feature = 'oneclick_integration_pipeline'    AND f.enabled = 1 AND f.active = 1 THEN 1 ELSE 0 END) AS pipeline,
       MAX(CASE WHEN f.feature = 'external_job_posting_integration' AND f.active = 1                   THEN 1 ELSE 0 END) AS ext_posting,
       MAX(CASE WHEN f.feature = 'oneclick_integration_php'         AND f.enabled = 1 AND f.active = 1 THEN 1 ELSE 0 END) AS php,
       MAX(CASE WHEN f.feature = 'aa_automated_delete'              AND f.enabled = 1 AND f.active = 1 THEN 1 ELSE 0 END) AS auto_delete,
       MAX(CASE WHEN f.option1 IN ('full', 'full_account')                                             THEN 1 ELSE 0 END) AS programmatic
FROM [64recs67o].dbo.p_sites s WITH(NOLOCK)
LEFT JOIN [64recs67o].dbo.p_sites_features f WITH(NOLOCK) ON f.site_id = s.site_id
WHERE s.site_id IN (25393, 17466, 5258, 4416, 15012, 20868, 5264, 26325, 23306)
GROUP BY s.site_id, s.site_name, s.site_type_id_jt;
```

---

> After the pipeline runs, append a dated revision below — never rewrite the history above it.
> One new section per post-implementation pass.

## 2026-09-18 — revision (pre-implementation)

Not a pipeline pass. D12's precondition changed while working CBS-4643, so it is recorded here
rather than left to surprise Phase 2.

**Changed**

- **D12's manual `ALTER` is superseded.** The decision itself stands — a green baseline is still
  required before `/ship`, for the reason D12 gives. What changed is how you get one: the drift is
  now recorded in `CoreAPI.Test/Scripts/000_schema_drift.sql` and applied before every run by
  `LegacyDatabaseSchemaFixture`, so a fresh container self-heals instead of needing the hand-run
  statement. Landed on the CBS-4643 branch (`55b6aa90`) and **not yet merged** — until it reaches
  `develop`, run the `ALTER` by hand as D12 originally said.
- **The baseline is now measured, not assumed.** `CoreAPI.Test` is **383 / 383** and
  `tests/CoreAPI.Tests.Integration` is **950 passed / 3 skipped**, both on a branch off current
  `develop`. D12 predicted 383/383 from a red run; that is now confirmed rather than expected.
- **One of the 85 failures was never container drift.** `PostingQueries_ChildPostingFilter_Tests`
  broke on the .NET 10 upgrade itself — EF Core 10 renamed a generated query parameter. Fixed
  separately (`81a54c2a`). D12's "57 existing *Job creation failed.* results" framing is right about
  the drift but was one test short of the whole red count.

**New open questions**

- **OQ3 now has a place to land.** If the seeded container turns out to be missing
  `job_distribution_transmit_site_setting`, the answer is an entry in `000_schema_drift.sql` — the
  same mechanism, additive and idempotent — not a hand-run statement and not a change to the
  integration-test schema scripts, which belong to the *other* suite. Note the two suites are
  separate: `tests/CoreAPI.Tests.Integration` builds its own schema from `Scripts/`, so OQ3 only
  bites the legacy project.

## 2026-09-18 — revision (prod verification)

Not a pipeline pass. The MCP servers came back, OQ1/OQ2/OQ4 were run against **`prod-64recs-mssql`,
reads only** (`mssql_execute_query` / `mssql_list_columns`; no write tool was called). **The result
reopens D2 and D8.**

### What the data says

**OQ1 — answered. D7 was right.**

| column | type |
| --- | --- |
| `transmit_setting_id` | `int NOT NULL` |
| `transmit_site_id` | `int NOT NULL` |
| `name` | `varchar(25) NOT NULL` |
| `value` | **`varchar(500) NOT NULL`** |
| `added` / `updated` | `smalldatetime NOT NULL`, default `getdate()` |
| `removed` | `smalldatetime NULL` |
| `active` | `bit NOT NULL`, default `1` |

Map `value` as `string`, compare `== "1"`. No change to D7.

**OQ2 — answered, and it fails the gate.**

- Sites carrying the setting at all: **113** — 108 with `'1'`, 5 with `'0'`.
- Strict `Common.IsCloud` sites (site active + pipeline enabled/active + `external_job_posting_integration` active + **not** php): **6,217. Flagged: 12. Unflagged: 6,205.**
- `pending_delete` / `pending_automated_delete` rows written in the last 30 days, **all writers**: 595,284 across 953 sites — 36,127 on flagged sites, **559,158 on unflagged**.
- Split by writer over the same window: `core_api_posting_stop` **173,776** · `usp_oneclick_posting_stop` 96,106 · everything else ~325k.
- **Core V2's own share — the in-scope blast radius under D1:** 173,776 rows across **754** sites, of which **1,231 (0.7%) are on flagged sites and 172,545 (99.3%) are not.**

So the rule as decided would suppress **~172.5k close requests per 30 days**, about **99.3%** of everything Core V2 currently sends. The ticket describes cleaning up 43 postings.

**OQ4 — answered.** All nine of Shiela's sites have **no setting row at all**, not even an explicit `'0'`:

| site_id | site_name | jt_type | pipeline | ext_posting | php | auto_delete | programmatic | setting row |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4416 | EmployOklahoma | 9 | 0 | 1 | 1 | 1 | 0 | none |
| 5258 | WorkForce West Virginia | 9 | 0 | 1 | 1 | 0 | 0 | none |
| 5264 | Hire Wyoming | 9 | 0 | 1 | 1 | 0 | 0 | none |
| 15012 | Indeed | 1 | 1 | 1 | 0 | 0 | 1 | none |
| 17466 | CompliancePost Veteran and Disability (OFCCP) | 3 | 1 | 1 | 0 | 0 | 1 | none |
| 20868 | Hire Patriots | 1 | 0 | 1 | 0 | 0 | 0 | none |
| 23306 | Colorado State University - College of Business | 1 | 0 | 1 | 1 | 1 | 0 | none |
| 25393 | JobTarget Programmatic | 1 | 1 | 1 | 0 | 0 | 1 | none |
| 26325 | CounselorJob.com | 1 | 0 | 1 | 0 | 0 | 0 | none |

### Why this breaks the design

**The rule cannot tell the 9 reported sites apart from the 745 others.** All of them have no setting
row. "Absent = not required" is not a discriminator here — it is a near-universal default.

**The 5 explicit `'0'` rows are the tell.** If absence already meant *not required*, nobody would
write an explicit `'0'`. Their existence says the column was meant to be **configured either way**,
and absence means *unconfigured*, not *no*. DBA-2636 could adopt "absent = skip" safely because it
runs over *non-integrated* postings, where that default is harmless. On the integrated path it is not.

**And it would break the ticket it exists to unblock.** Site **25461 — SEEK | JobsDB | JobStreet —
has no `requires_pending_delete` row either.** Under D2, every SEEK stop takes the
expire-without-close path, including early ones. PJO-11160's AC says the opposite in as many words:

> A `closePostedPositionProfile` request is still sent when a posting is stopped before completing
> its product duration.

That is a direct contradiction, not a tuning problem. **D2 as decided would ship the failure mode
PJO-11160 was filed to prevent.**

### What stands and what does not

- **Reopened: D2** (absent → expire) and **D8** (data-driven for all sites, no flag). Both rest on
  the assumption this data just refuted.
- **Unaffected: D1, D3, D4, D5, D6, D7, D9, D10, D11, D12.** The duration semantics, the five write
  sites, the `PostingUpdate` plumbing, the transmit suppression, the entity and lookup shape, the
  test strategy and the baseline gate are all independent of how the *site* predicate is defined.
- **OQ3 is untouched** and stays open, but it is moot until D2/D8 resolve.

### Options for the re-decision — not decided, Neru's call

- **(A) Invert the default** — bypass only on an explicit `value = '0'`; absence means *requires
  deletion*, today's behaviour. Safe, and it makes the 5 explicit `'0'` rows meaningful. But it fixes
  **none** of Shiela's 9 sites, because none of them have a row. Ships a mechanism with no data behind
  it and leaves the reported bug open pending a backfill.
- **(B) Keep the decided semantics, but gate on a backfill** — the rule is right, the data is not
  ready. Requires DBA to populate `requires_pending_delete` across the integrated estate first. That
  is a data project of ~6,200 sites and is not ours.
- **(C) Ship the duration half only.** D3/D4 do not need the site predicate at all if the rule becomes
  *duration reached → expire, regardless of flag*. That satisfies PJO-11160's primary AC (natural
  expiry → Expired, no close) and leaves early stops on today's path, close request intact. It does
  **not** address Shiela's DES-noise complaint. Smallest safe step, and it unblocks the ticket that
  CBS-4646 blocks.
- **(D) Site allowlist** — previously rejected, but the data makes it look better than it did: 25461
  plus the 9 reported sites, expanded as the setting gets populated. Still config nobody prunes.

**My recommendation: (C) now, (B) as the follow-up**, and take the numbers above back to Shiela and
Nikole — the 99.3% figure reframes the ticket from "cleanup" to "estate-wide behaviour change", which
is a product decision, not an implementation detail.

### Queries as actually run

Verbatim, all against `prod-64recs-mssql` on **2026-09-18**. The originals in
[How to close them](#how-to-close-them) are kept for the record but two of them do not execute —
use these. **Every count is a point-in-time reading; the 30-day windows will drift, so re-run rather
than quote these numbers as current.**

**OQ1** — not SQL. `mssql_list_columns` with `tableName: "dbo.job_distribution_transmit_site_setting"`.
Simpler than the `sys.columns` join and returns defaults and nullability too.

**OQ2a — values present and site counts.** Ran as written in *How to close them*, unchanged.
Returned `'1'` → 108 sites, `'0'` → 5 sites.

**OQ2b — strict `IsCloud` sites, flagged vs not.** Mirrors `Common.IsCloud` exactly (site active +
pipeline enabled/active + `external_job_posting_integration` active + **not** php enabled/active).
Returned 6,217 / 12 / 6,205.

```sql
SELECT COUNT(*) AS cloud_sites_strict, SUM(x.has_flag) AS flagged, SUM(1-x.has_flag) AS unflagged
FROM (
  SELECT s.site_id,
    CASE WHEN EXISTS (
      SELECT 1 FROM [64recs67o].dbo.job_distribution_transmit_site ts WITH(NOLOCK)
      JOIN [64recs67o].dbo.job_distribution_transmit_site_setting tss WITH(NOLOCK)
        ON tss.transmit_site_id = ts.transmit_site_id
      WHERE ts.site_id = s.site_id AND ts.active = 1 AND tss.active = 1
        AND tss.name = 'requires_pending_delete' AND tss.value = '1'
    ) THEN 1 ELSE 0 END AS has_flag
  FROM [64recs67o].dbo.p_sites s WITH(NOLOCK)
  WHERE s.active = 1
    AND EXISTS (SELECT 1 FROM [64recs67o].dbo.p_sites_features f WITH(NOLOCK)
                WHERE f.site_id = s.site_id AND f.feature = 'oneclick_integration_pipeline'
                  AND f.enabled = 1 AND f.active = 1)
    AND EXISTS (SELECT 1 FROM [64recs67o].dbo.p_sites_features f WITH(NOLOCK)
                WHERE f.site_id = s.site_id AND f.feature = 'external_job_posting_integration'
                  AND f.active = 1)
    AND NOT EXISTS (SELECT 1 FROM [64recs67o].dbo.p_sites_features f WITH(NOLOCK)
                    WHERE f.site_id = s.site_id AND f.feature = 'oneclick_integration_php'
                      AND f.enabled = 1 AND f.active = 1)
) x
```

**OQ2c — writer split over 30 days.** The `GROUP BY created_by` version times out; this form returns.
Returned `core_api_posting_stop` 173,776 · `usp_oneclick_posting_stop` 96,106 · all 595,284.

```sql
SELECT
  SUM(CASE WHEN jss.created_by = 'core_api_posting_stop'     THEN 1 ELSE 0 END) AS core_api_v2,
  SUM(CASE WHEN jss.created_by = 'usp_oneclick_posting_stop' THEN 1 ELSE 0 END) AS proc_posting_stop,
  COUNT(*) AS all_rows
FROM [64recs67o].dbo.jobs_sites_status jss WITH(NOLOCK)
WHERE jss.status IN ('pending_delete','pending_automated_delete')
  AND jss.added >= DATEADD(day,-30,GETDATE())
```

**OQ2d — the decisive one: Core V2's own writes, flagged vs not.** Returned 173,776 rows / 754 sites
/ 1,231 flagged / 172,545 unflagged. Drop the `created_by` predicate for the all-writers figure
(595,284 / 953 / 36,127 / 559,158).

```sql
SELECT COUNT(*) AS core_api_rows_30d, SUM(x.has_flag) AS on_flagged,
       SUM(1-x.has_flag) AS on_unflagged, COUNT(DISTINCT x.site_id) AS distinct_sites
FROM (
  SELECT js.site_id,
    CASE WHEN EXISTS (
      SELECT 1 FROM [64recs67o].dbo.job_distribution_transmit_site ts WITH(NOLOCK)
      JOIN [64recs67o].dbo.job_distribution_transmit_site_setting tss WITH(NOLOCK)
        ON tss.transmit_site_id = ts.transmit_site_id
      WHERE ts.site_id = js.site_id AND ts.active = 1 AND tss.active = 1
        AND tss.name = 'requires_pending_delete' AND tss.value = '1'
    ) THEN 1 ELSE 0 END AS has_flag
  FROM [64recs67o].dbo.jobs_sites_status jss WITH(NOLOCK)
  JOIN [64recs67o].dbo.jobs_sites js WITH(NOLOCK) ON js.id = jss.jobs_sites_id
  WHERE jss.status IN ('pending_delete','pending_automated_delete')
    AND jss.created_by = 'core_api_posting_stop'
    AND jss.added >= DATEADD(day,-30,GETDATE())
) x
```

**OQ4 — the nine sites, with flag state.** The *How to close them* version plus two columns:
`flagged` (value `'1'` present) and `has_setting_row` (any `requires_pending_delete` row at all).
The second column is what proved absence rather than an explicit `'0'`. Swap the `IN` list for
`s.site_id = 25461` to re-check SEEK — it returned `setting_rows = 0`.

### Tool gotchas

- **CTEs are rejected** — `WITH …` fails the "Only SELECT queries are allowed" guard. Rewrite with
  `EXISTS` subqueries or a derived table.
- **`SUM(CASE WHEN EXISTS(...))` is rejected** — "aggregate on an expression containing a subquery".
  Put the row-level `CASE` in a derived table and aggregate outside it.
- **Grouping `jobs_sites_status` by `created_by` / `process`** over a 7- or 30-day window **times out
  at 60s**, with or without the `jobs_sites` join. `SUM(CASE WHEN created_by = …)` over the same
  window returns in time.
