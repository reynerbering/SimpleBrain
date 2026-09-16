---
type: design-doc
ticket: CBS-4654
team: CBS
status: in progress
repos:
  - CoreAPI
updated: 2026-09-17
---

# CBS-4654 — Posting read timeouts

- **Status:** in progress — raw dump, not yet grilled
- **Ticket:** [[tickets/CBS-4654.md]] — *file does not exist yet; Jira title/status unverified (Atlassian + GitLab MCP both failed to connect 2026-09-17)*
- **Grilled:** not yet — no Phase 1 session has been run. `grilled:` deliberately omitted from frontmatter rather than back-filled.
- **Last touched:** 2026-09-17

> ⚠️ Raw capture from a review of MR !1379. The findings below are verified; the conclusion about
> *what actually causes the timeouts* is still open. Continue from "Open questions".

## TODO

- [ ] Decide option A (land !1379 as a readability refactor) or option B (hold it) — see [Options](#options)
- [ ] Find the real root cause: pull `query_hash` / plan history from Query Store or `sys.dm_exec_query_stats` during a burst window — see [Next step to settle it](#next-step-to-settle-it)
- [x] ~~Check the `r_order_item_id` column type~~ — **done 2026-09-17, result inverts the plan**: the
      columns are genuinely `int` vs `bigint` **in the schema**, entities already match. Aligning the
      entity cannot kill the `CAST`. Re-verify against prod, then decide `ALTER` vs leave. See below.
- [ ] Verify the prod burst numbers independently in Datadog — currently quoted from the commit message, unverified
- [ ] Grill this (Phase 1) before any implementation, then set `grilled:` in the frontmatter

## What was reviewed

- MR [!1379](https://gitlab.com/jobtarget/platform/core-api/CoreAPI/-/merge_requests/1379) — 1 commit `c7b0cb69`, 3 files, off `develop` at `e57e95be`.
- Title: *"CBS-4654: drop the 348M-row child-posting EXISTS from the Posting read path"*.
- Reviewed by fetching `refs/merge-requests/1379/head` locally — the `gitlab` MCP server timed out, so **MR discussion and approvals were not read**. Code only.
- Files touched: `CoreAPI.DataAccess/Features/Common/Filters/PostingFilters.cs`, `CoreAPI.DataAccess/Features/PostingFeatures/PostingQueries.cs`, new `CoreAPI.Test/Service_Tests/PostingQueries_ChildPostingFilter_Tests.cs`.

**What it does:** removes the `!omitProgrammaticPostings ||` short-circuit from inside `FilterChildPostings`, and has the three read call sites add the predicate conditionally instead.

## Verdict

**Safe but inert. It does not fix CBS-4654.** Do not merge it as the fix.

## The stated root cause does not reproduce

The commit message claims:

> EF renders a captured bool as a parameter, so the generated SQL was `@param = 0 OR NOT EXISTS(...)`

- EF Core **7.0.20** (pinned in `CoreAPI.DataAccess.csproj:17`) does **not** do this.
- A captured `bool` inside a short-circuiting `||` is **constant-folded at translation time**, not parameterized. The optimizer then prunes the branch entirely.
- Pre-MR code, `omitChildPostings: false`, generated SQL in full:

```sql
SELECT [j].[id], [j].[active], ... FROM [jobs_sites] AS [j]
WHERE [j].[job_id] = @__jobId_Value_0
```

No `r_orders_items_links`. No `@param = 0 OR`.

### Evidence — old vs new generated SQL

Dumped `GetBasePostingsQuery(...).ToQueryString()` from both implementations, both flag values, then diffed the files:

| `omitChildPostings` | old vs new SQL |
| --- | --- |
| `false` | **byte-identical** |
| `true` | **byte-identical** |

**Consequences for the diagnosis:**

- The dead EXISTS was never sent to SQL Server on the default path — it was already eliminated in C#, before SQL generation.
- `true` and `false` already produced two *different* SQL texts, so they already had **separate plan-cache entries**. The commit's "one cached plan inherited by every task in every AZ" mechanism cannot be what happened.
- Merging changes zero query plans in prod. **The 14 bursts remain unexplained.**

## The new tests pass against unmodified `develop`

- Ran the MR's own `PostingQueries_ChildPostingFilter_Tests` against develop's `PostingFilters.cs` + `PostingQueries.cs`. Only edits needed: `private` → `internal` on `GetBasePostingsQuery`, and the 2-arg call in the fourth test.
- **4/4 passed.**
- They are not regression tests. They assert EF behaviour that was already true, so nothing about them could have caught the bug or can catch its return.

## The read path still hits the 348M-row table — on every request

The strongest remaining suspect. The `PostingOrderData` sub-select in the projections of **both** `GetPostingAsync` (`PostingQueries.cs:93`) and `GetPostingsAsync` (`PostingQueries.cs:175`) correlates against `r_orders_items_links` **per row, regardless of `omitChildPostings`**:

```sql
OUTER APPLY (
  SELECT TOP(1) ... FROM [r_orders_items] AS [r] INNER JOIN [r_orders] AS [r1] ...
  WHERE EXISTS (SELECT 1 FROM [r_orders_items_links] AS [r0]
                WHERE [r0].[type] = N'job' AND [r0].[link_id] = [j].[id]
                  AND CAST([r0].[r_order_item_id] AS bigint) = [r].[r_order_item_id])
) AS [t]
```

- On the **default** path, and it **scales with page size**.
- The MR's test `..._Does_Not_Touch_OrderItemLinks_...` gives false assurance: it asserts on `GetBasePostingsQuery` in isolation, which is **not** the SQL that runs in production.

### Non-sargable CAST on the big table

- `OrderItemLinkEntity.OrderItemId` is `int`; `OrderItemEntity.Id` is `long`.
- EF therefore emits `CAST([r0].[r_order_item_id] AS bigint)`, killing any seek on that column of the 348M-row table.
- **Checked 2026-09-17** against the **local seeded test container** (`coreapi-test-sql`, db `64recs67o`)
  — *not prod*, and the test schema may lag. `sys.columns` says:

  | Table | Column | Type |
  | --- | --- | --- |
  | `r_orders_items` | `r_order_item_id` | **bigint** |
  | `r_orders_items_links` | `r_order_item_id` | **int** |

  ⚠️ **This inverts the TODO.** The entities already match the DB — `int` maps an `int` column,
  `long` maps a `bigint` column. So the `CAST` is **not** an entity/DB mismatch and **cannot be
  removed by aligning `OrderItemLinkEntity.OrderItemId` to `long`**; doing that would misdeclare the
  column. The mismatch is **in the schema itself**, across the two sides of the join.
  - Real options are now: `ALTER` `r_orders_items_links.r_order_item_id` to `bigint` (a DDL change on
    a 348M-row table — not cheap), or leave it and stop calling it a quick win.
  - **Must be re-verified against prod `64recs67o`** before acting. MSSQL MCP was down 2026-09-17.

## Smaller findings

- `PostingFilters.cs:33` — `FilterInactivePostings` keeps `!omit || posting.Active == true`, two lines below the new XML doc calling that exact pattern a plan hazard. The file contradicts itself. Since the premise is wrong, fix the **comment**, not the code.
- `GetBasePostingsQuery` widened `private` → `internal` purely for tests that add no value. If the tests go, the visibility change should too.
- `StringAssert.Contains("__jobId_Value", sql)` asserts on EF's internal parameter-naming. Breaks on an EF upgrade, protects nothing.

## What is genuinely fine in the MR

- The refactor is semantically correct — `FilterChildPostings(dc, false)` really was `posting => true`.
- All three call sites updated consistently; no stale callers of the old signature anywhere in the repo.
- `GetPostingsCountAsync` and `GetPostingsAsync` stay in sync.
- Solution builds clean (0 errors).

## Options

- **A — land as a pure readability refactor.** Rewrite the commit message and the XML doc comment to drop the perf claim; drop or rewrite the tests. Keeps a real (small) readability gain.
- **B — hold the MR and reopen the diagnosis.** Nothing is lost by waiting; the MR fixes nothing either way.

Not decided. Needs grilling.

## Open questions

- OPEN QUESTION: what actually causes the bursts? The `OUTER APPLY` above is the first place to look, but it is a hypothesis, not a finding.
- OPEN QUESTION: is it even a plan problem? Blocking / lock escalation on `jobs_sites` would produce a similar "Posting-only, everything else on the same context fine" signature.
- OPEN QUESTION: option A or option B.
- OPEN QUESTION: the prod burst numbers in the commit message (14 bursts in 14 days, largest 89 failed requests in 2m18s on 2026-09-08, 108k req/hr on a quiet day) were **taken from the commit message, not independently verified**. Datadog MCP was down.

### Next step to settle it

- Pull `query_hash` / plan history for the timing-out statement from Query Store or `sys.dm_exec_query_stats` during a burst window.
- The "other domains on the same contexts and pools failed zero times" signature does still point at a **Posting-specific statement** — that part of the original reasoning holds.

## How to reproduce the SQL evidence

1. `git fetch origin refs/merge-requests/1379/head:mr-1379` in `C:\JT Repositories\CoreAPI`.
2. Worktree it, then `dotnet build CoreAPI.Test/CoreAPI.Test.csproj`.
3. Add a scratch NUnit fixture that news up `DataContext` with `.UseSqlServer("Server=(local);...")` — **no DB is ever opened**, `ToQueryString()` only needs the provider for translation.
4. Call `PostingQueries.GetBasePostingsQuery(...)` for `omitChildPostings` true and false, write `.ToQueryString()` to files.
5. `git checkout e57e95be -- PostingFilters.cs PostingQueries.cs`, patch `private` → `internal`, rebuild, dump again, `diff`.

Test command is now **pinned in [[protocols/coding-standards.md]]** — the only copy. Filter a single
fixture with `--filter "FullyQualifiedName~<class>"`. .NET 6 runtime present alongside SDK 9.0.317.

⚠️ **The suite needs the local MSSQL container up** (`docker start coreapi-test-sql`). Without it
the run is 192 failed / 175 passed — all environmental. That precondition was not known when this
doc was written on 2026-09-17; the earlier note here claimed the command was verified without
recording it. Details are in the protocol, not repeated here.
