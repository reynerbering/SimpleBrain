---
name: investigate-ticket
description: Trace a JobTarget bug/ticket to root cause across Jira → Core code (GitLab) → CloudWatch logs → SQL DB, aligning timestamps to attribute the failure to the right service, then post an evidence-backed Jira comment. Use when a ticket blames a service (e.g. "Core updates the posting late") and you need to confirm or refute it with cross-system evidence.
user-invocable: true
# Read-only investigation tooling + the single Jira mutation (comment) needed to report.
# Deliberately omits *_execute_write_query and Jira transition/update tools.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - ToolSearch
  - Bash
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  - mcp__claude_ai_Atlassian__lookupJiraAccountId
  - mcp__claude_ai_Atlassian__atlassianUserInfo
  - mcp__claude_ai_Atlassian__addCommentToJiraIssue
  # CloudWatch access is via the `cloudwatch` skill (AWS CLI over Bash) — see the CloudWatch reference below.
  - Skill
  - mcp__gitlab__search_projects
  - mcp__gitlab__get_repository_tree
  - mcp__gitlab__get_file_contents
  - mcp__gitlab__get_merge_request_diff
  - mcp__gitlab__get_commits
  - mcp__mssql__mssql_execute_query
  - mcp__mssql__mssql_get_connection_info
  - mcp__mssql__mssql_search_tables
  - mcp__mssql__mssql_get_table_info
  - mcp__mssql__mssql_list_columns
  - mcp__mssql__mssql_list_databases
  - mcp__mssql-uat__mssql_execute_query
  - mcp__mssql-uat__mssql_list_databases
---

# investigate-ticket — Cross-system root-cause investigation (JobTarget)

Playbook for attributing a data/timing bug to the correct service by lining up evidence from **Jira + GitLab (Core code) + CloudWatch + the SQL DB**. Built from the CBS-4113 investigation (Indeed Pick & Post additional-info fields). The core technique is **timestamp alignment across systems** to separate "service wrote it late" from "service was called late / never called."

Arguments: `$ARGUMENTS` (usually a Jira key like `CBS-4113`, optionally a hypothesis to test).

---

## Method (phases)

1. **Read the ticket + all comments.** Get the issue with `mcp__claude_ai_Atlassian__getJiraIssue` (cloudId `jobtarget.atlassian.net`, `responseContentFormat: markdown`). Comment ADF often blows the token limit — if so it saves to a file; parse it with PowerShell `ConvertFrom-Json` and a recursive text extractor over `comment.comments[].body.content`. Note what each commenter claims and which service got blamed.
2. **Identify the services & repos.** Map the failing flow to a CloudWatch log group and a GitLab repo. For posting/Core work: caller is usually `partnermarketplace` (its ECS log group in the prod account); Core API repo is `jobtarget/platform/core-api/CoreAPI` (project ID **34542182**).
3. **Trace the code path.** Is the write **synchronous** (inline `SaveChangesAsync`) or **async** (queue/SNS/SQS)? This decides whether "the service updated late" is even possible. Delegate broad repo reading to an `Explore` agent (GitLab **global code search is disabled** — navigate by `get_repository_tree` + `get_file_contents`; watch `.gitmodules`).
4. **Pull CloudWatch (the call side).** Find when the call was *made* and with what payload (see the CloudWatch reference below — invoke the `cloudwatch` skill for auth + query mechanics).
5. **Pull the DB (the write side).** Find when the row actually *landed*.
6. **Align timestamps** (see the critical gotcha below) and attribute: call-time ≈ write-time ⇒ the service is innocent; the delay is in *when it was called* or *whether it was called at all*.
7. **Reconfirm on prod** before asserting ownership (snapshots can be stale/seeded — see DB identities).
8. **Post findings** as a Jira comment (see posting gotchas). Default to **neutral/evidence-only** framing unless told otherwise; confirm before posting (outward-facing).

---

## ⚠️ The critical gotcha: timezone alignment

**CloudWatch timestamps are UTC. The SQL DB stores Eastern (UTC−4, EDT).** If you compare them raw you'll see a phantom ~3–4h "lateness" that doesn't exist. Always convert before comparing. Confirm the offset per session:
```sql
SELECT DATEDIFF(MINUTE, SYSUTCDATETIME(), SYSDATETIME()) AS offset_min  -- expect -240 (EDT)
```
Also: `jobs_info_medium.added` is `smalldatetime` → **rounds to the nearest minute**, so a call at `12:41:46` shows as a write at `12:42`. A 0–1 min "gap" = same event, not latency.

---

## CloudWatch reference

Query via the **`cloudwatch` skill** — invoke it (Skill tool) for the auth bootstrap (`--profile shared-platform.obs`, account `613437596725`, `us-east-1`) and Logs Insights mechanics. Everything below is the JobTarget-specific query shape for the posting flow.

- Timestamps: UTC (same as the DB gotcha above — DB is EDT).
- Caller service for postings: `partnermarketplace` (prod). **Find its log group first** — don't guess the name:
  ```bash
  aws --profile shared-platform.obs logs describe-log-groups \
    --include-linked-accounts --region us-east-1 \
    --log-group-name-pattern 'partnermarketplace' --output json
  ```
  (typical shape `/ecs/prod-partnermarketplace-app`). Grab its ARN (no trailing `:*`) for `--log-group-identifiers`.
- The outbound Core call logs with message template `@mt` matching `CoreApiService.UpdatePosting*`. Payload is a nested `request` object → `{SiteId, JobId, CustomFields:[{Name,Value}]}`. In CloudWatch these are structured-JSON fields, addressable as `request.JobId`, `request.SiteId`, `@mt`.
- Find a specific call (Logs Insights query string — write to a file, pass `--query-string file://...`):
  ```
  fields @timestamp, @message, @mt, request.JobId, request.SiteId
  | filter @mt like /CoreApiService.UpdatePosting/
  | filter request.JobId = <id>
  | sort @timestamp asc
  | limit 100
  ```
  If the structured fields don't resolve (logger flattens differently per service), fall back to a raw-substring match on `@message` for the JobId and inspect the full event JSON to confirm field paths.
- **Aggregate before listing** (see cloudwatch skill): use `stats count() by bin(1h)` to get call counts/timing cheaply before pulling raw events.
- Retention varies by group (ECS `*-app` typically 30–90 days) — confirm `retentionInDays` from `describe-log-groups` before claiming "logs are gone." Longer window than Datadog's ~10–15 days.
- **Not everything is logged**: in one 4-day window site-15012 had ~521 DB field-writes but only ~45 `UpdatePosting` calls — most writes happen on the *at-creation* path, and the `UpdatePosting`/inference call is the *fix-up* path. A missing log ≠ a missing write; cross-check the DB.

## SQL DB reference

Three connections, all DB `64recs67o` (obfuscated name), all **EDT**:
- `mcp__mssql` → **DEV** `JTAWSSQLDEV05` (masked restore; recent rows may be Faker-synthetic, e.g. "Donnelly, Kulas and Kohler"; newest prod rows may be absent).
- `mcp__mssql-uat` → **STAGING** `JTAWSSQLSTAG` (second independent restore — good for corroboration).
- **PROD** `JTAWSSQL01` — no MCP; the user supplies a read-only connection string. Connect via PowerShell `System.Data.SqlClient` (or `sqlcmd`). **Credential hygiene:** write the string to a file (e.g. `$HOME\.proddb_conn`), read it inside one PowerShell call, never echo it, and `Remove-Item` it when done. Verify identity first (`DB_NAME()`, `@@SERVERNAME`, offset). SELECT-only.
- MCP query quirk: the wrapper forbids `ORDER BY` unless `TOP`/`OFFSET` is present, and chokes on trailing `;`/newlines — use `SELECT TOP 100 ... ORDER BY ...` on a single line.

Key tables (postings):
- `dbo.jobs_info_medium` — additional-info fields. Keyed by `(job_id, site_id, item)`, **one shared row per key** (not per posting). Columns: `val`, `added`/`updated`/`removed` (smalldatetime), `active`. **`site_id = NULL` = job-level default (from original job creation); `site_id = 15012` = the site-specific value that actually transmits.** "Missing" usually means the site-specific row was never written while the NULL-level one exists.
- `dbo.jobs_sites` — postings. `id` = posting_id, `job_id`, `site_id`, `source` (`'posted'` = Pick & Post order; `'spider'` = scraped), `added`. **A job can have many postings at one site** — so when measuring "field added X late", align the shared field row to the *correct* posting instance, or you'll overstate the delay (a real artifact in CBS-4113).
- Indeed = `site_id 15012`; items: email `58166`, zip `50058`, job_type `66`.

## GitLab reference

- Global code search is **disabled** (403) — use `get_repository_tree` (recursive) + `get_file_contents`; check `.gitmodules`.
- Core posting writes: `CoreAPI.DataAccess/Features/PostingFeatures/PostingPatchCommands.cs` (`UpdateCustomFieldsAsync` → `UpdateJobInfoFieldAsync` → `SaveChangesAsync`, synchronous) and `PostingCreateCommands.cs`.
- For broad reads, spawn an `Explore` subagent with the exact paths/symbols to find.

## Posting findings to Jira — gotchas

- `mcp__claude_ai_Atlassian__addCommentToJiraIssue`, cloudId `jobtarget.atlassian.net`.
- **@-mentions:** in `contentFormat: markdown` the `[~accountid:<id>]` syntax gets **escaped to literal text** (no notification). For working mentions use `contentFormat: adf` with a `mention` node: `{"type":"mention","attrs":{"id":"<accountId>","text":"@Name"}}`. Resolve IDs with `lookupJiraAccountId`.
- There is **no edit-comment tool** — get it right before posting; a follow-up comment is the only fix.
- Tables/code render fine in markdown; mentions are the only thing that needs ADF. A pragmatic split: long body in markdown, a short ADF follow-up that does the tagging.
- Sign on the user's behalf only when asked; the comment author is already the authenticated account.

---

## Output

A concise attribution: **which service is/ isn't at fault and why**, an alignment table (call-time vs write-time, both in ET), CloudWatch Logs Insights links (or the query + log group + window so it's reproducible), and the upstream lever to fix. Persist durable conclusions to memory. Related prior finding: `cbs-4113-indeed-pickpost-missing-fields` in `MEMORY.md`.

---

## Worked example — CBS-4113 (template)

**Hypothesis under test:** "Core's `UpdatePosting` call succeeds but Core writes the posting late." → **Refuted.**

**Step 1 — code:** `PostingPatchCommands.cs` writes inline via `SaveChangesAsync` (no queue). So "wrote late" is only possible if the *call* came late. Hypothesis already on shaky ground.

**Step 2 — alignment table** (the deliverable shape). Pull the CloudWatch call (`@timestamp`, UTC) and the DB `jobs_info_medium.added` (ET), convert CloudWatch UTC→ET (−4h), and compare:

| Job | Posting created (ET) | UpdatePosting call (UTC → ET) | DB `added` (ET) | Call→write gap |
|---|---|---|---|---|
| 40305688 | 09:31 | 16:41:46Z → 12:41 | 12:42 | ≤1 min |
| 40624419 | 08:31 | 12:31:00Z → 08:31 | 08:31 | 0 min |

Gap is 0–1 min (smalldatetime rounding) in **every** case ⇒ Core writes the instant it's called. The reported "3.2h late" was (a) CloudWatch-UTC vs DB-ET not converted, and (b) the shared `(job_id,site_id,item)` row compared against an earlier posting instance of a multi-posting job.

**Step 3 — two paths:** ~80% of writes land at posting creation (no `UpdatePosting` call); the ~20% fix-up path calls `UpdatePosting` late (inference runs after order) or never (reposts) ⇒ "late"/"missing". **The lever is upstream (inference-call timing / repost re-population), not Core.**

**Step 4 — reconfirm on prod** (`JTAWSSQL01`, user-supplied read-only string) before asserting; corroborate against the STAGING restore.

**Step 5 — post:** neutral/evidence-only comment, ADF for the @mentions, markdown body for the tables/links.

Reproducible CloudWatch evidence (Logs Insights doesn't have stable per-result permalinks — include the log group + query + window so anyone can re-run it):
```
log group: /ecs/prod-partnermarketplace-app   (confirm exact name via describe-log-groups)
window:    <startUTC> → <endUTC>
query:     fields @timestamp, @mt, request.JobId | filter @mt like /CoreApiService.UpdatePosting/ | filter request.JobId = <ID> | sort @timestamp asc
```
