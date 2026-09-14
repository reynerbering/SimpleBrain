---
name: cloudwatch
description: Query AWS CloudWatch (Logs, Logs Insights, Metrics, RUM, X-Ray/APM Spans, Events) via the central observability sink in the Shared-Platform account. Use when the user asks about AWS logs, log groups, CloudWatch metrics, real-user-monitoring (RUM) sessions, X-Ray traces, ECS/Lambda logs, or wants to query observability data across linked AWS accounts. The skill self-bootstraps the SSO profile on first run, so authentication is automatic — no need to ask the user to log in.
---

# AWS CloudWatch (Observability) Skill

## Authentication (automatic — do not ask the user)

Bootstrap silently. The skill uses a managed profile `shared-platform.obs` whose `credential_process` is wired to `aws-sso-util`, so once configured the AWS CLI handles token refresh internally and every command just works with `--profile shared-platform.obs`.

Flow on first run (run all steps yourself; do not prompt the user):

```bash
# 1. Probe. If this succeeds, jump straight to querying.
aws --profile shared-platform.obs sts get-caller-identity --output json

# 2. If the profile is missing, create it (idempotent).
aws-sso-util configure profile shared-platform.obs \
  --account-id 613437596725 \
  --role-name ObservabilityReadOnlyAccess \
  --region us-east-1 \
  --non-interactive

# 3. If the SSO session is stale (ExpiredToken), re-login via ANY existing SSO-configured profile —
#    the SSO token is shared across all profiles on the same start URL. Pick one from
#    `aws configure list-profiles` (e.g. prod-coreapi.readonly). This opens the browser for the user.
aws sso login --profile prod-coreapi.readonly
```

Re-run step 1 after step 3 to confirm. From here, `aws --profile shared-platform.obs ...` works for every command in this skill — no manual env-var export needed.

> Shell note: snippets in this file use bash-style line continuations (`\`). On PowerShell, swap `\` for a backtick (`` ` ``); on `cmd.exe`, use `^` or fold the command onto one line. The AWS CLI args themselves are identical.

## Where to query — Shared-Platform account

The central observability sink lives in account **`613437596725` (`Shared-Platform`)**, region **`us-east-1`**. From here, **`ObservabilityReadOnlyAccess`** can query logs, metrics, RUM, X-Ray and Application-Signals data from **every linked account** via CloudWatch Cross-Account Observability (OAM).

Sink ARN: `arn:aws:oam:us-east-1:613437596725:sink/9aaea300-3355-4e73-b571-5a3a0a8d22bf`

Linked accounts (read via `aws oam list-attached-links --sink-identifier <sink-arn>`) include prod/uat/qa/sb environments across the org. The list grows over time — re-query if a service's logs aren't where you expect.

### Resource inventory (fallback only)

A pre-built inventory of AWS resources across accounts is available at <https://nocagent.jobtarget.com/inventory/cw_inventory.jsonl> (JSONL). **Only reach for it when you need an AWS resource or detail that isn't reachable through the Shared-Platform observability sink** — e.g. an account/resource not linked to the sink. For everything queryable via `shared-platform.obs`, query directly; don't pull the inventory.

### Using credentials in commands

Pass `--profile shared-platform.obs` to every AWS CLI call. The CLI invokes `aws-sso-util credential-process` under the hood and refreshes session tokens automatically while the SSO session is alive. No env-var export needed.

```bash
aws --profile shared-platform.obs logs describe-log-groups --include-linked-accounts ...
aws --profile shared-platform.obs cloudwatch get-metric-statistics ...
```

## Query Strategy (read first)

### Discoverability first — list before you query

Don't guess log-group names. They differ per account naming convention (`/ecs/...`, `/aws/lambda/...`, `/aws/ecs/...-ecs-exec`, `/aws/rds/...`, `/aws/vendedlogs/...`, etc.). Enumerate them first:

```bash
aws --profile shared-platform.obs logs describe-log-groups \
  --include-linked-accounts \
  --account-identifiers <linked-account-id> \
  --region us-east-1 \
  --log-group-name-prefix '/ecs/prod-' \
  --output json
```

Drop `--account-identifiers` to scan every linked account at once (returns thousands of groups — page through it). `--log-group-name-prefix` is cheap and usually narrows fast. For substring search across all linked accounts, use `--log-group-name-pattern '<substr>'` instead.

### Retention varies by group

Common patterns observed across the org (verify per service):

- ECS `*-app` and `*-otel`: 30–90 days
- ECS `containerinsights/*/performance`: 1 day
- ECS `*-ecs-exec`: 30–90 days
- Lambda `/aws/lambda/...`: 14–90 days
- RDS `/aws/rds/...`: 7 days

If a target date is older than ~15 days, check the group's `retentionInDays` before claiming "logs are gone."

### Aggregation first, raw logs second

For "find error types" / "categorize" / "top N" questions, drive the query with `aws logs start-query` filter expressions that **count** before fetching raw events. Logs Insights aggregations look like:

```
fields @timestamp, @message
| stats count() by bin(1h)
```

or group by message template / source class:

```
fields @timestamp, SourceContext, @mt
| filter @l = "Error"
| stats count() as errs by SourceContext, @mt
| sort errs desc
| limit 50
```

Then fetch 2–3 raw events per top bucket for context. This avoids one chatty error type drowning out the long tail.

Caveat: structured JSON logs (Node.js pino/winston, etc.) often emit a unique `trace_id` per request, so `stats count() by @message` produces one bucket per request. In that case, group by stable fields the service actually sets — typically `level`, `name`, `status`, `message` (without the variable parts) or `errorObject.message`.

## API Reference

All snippets assume credentials are exported via the boilerplate above. Replace `<acct>` with the linked account ID and `<group>` with the log group name (no trailing `:*`). Where a snippet writes a temp file, use your platform's temp dir (`/tmp/...` on Mac/Linux, `%TEMP%\...` on Windows, `$env:TEMP\...` in PowerShell).

### Logs Insights query (cross-account)

```bash
# Write the query to a file (avoids shell quoting hell)
cat > /tmp/cwq.txt <<'EOF'
fields @timestamp, @message, @log
| filter @message like /your-keyword/
| sort @timestamp asc
| limit 100
EOF

START=$(date -u -d '2026-04-24T14:00:00Z' +%s)   # GNU date; on macOS use `date -j -f`
END=$(date -u -d '2026-04-24T16:00:00Z' +%s)

# IMPORTANT: log-group-identifiers takes ARNs WITHOUT trailing :* (different from policy syntax)
aws --profile shared-platform.obs logs start-query \
  --log-group-identifiers \
    'arn:aws:logs:us-east-1:<acct>:log-group:<group>' \
    'arn:aws:logs:us-east-1:<acct>:log-group:<another-group>' \
  --start-time $START \
  --end-time $END \
  --query-string file:///tmp/cwq.txt \
  --region us-east-1 --output json

# Poll until Complete
aws --profile shared-platform.obs logs get-query-results \
  --query-id <queryId> --region us-east-1 --output json
```

**Status values**: `Scheduled`, `Running`, `Complete`, `Failed`, `Cancelled`. Poll with a ~2s sleep between checks. Output includes `statistics.recordsScanned` / `recordsMatched` so you can show progress.

### Logs Search (simple, point-in-time)

```bash
aws --profile shared-platform.obs logs filter-log-events \
  --log-group-identifier 'arn:aws:logs:us-east-1:<acct>:log-group:<group>' \
  --start-time <epoch-ms> --end-time <epoch-ms> \
  --filter-pattern 'ERROR' \
  --region us-east-1 --output json
```

Note: `filter-log-events` uses `--log-group-identifier` (singular) and **epoch milliseconds**, while `start-query` uses `--log-group-identifiers` (plural) and **epoch seconds**. Easy to mix up.

### Metrics (CloudWatch Metrics)

```bash
aws --profile shared-platform.obs cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=<svc> Name=ClusterName,Value=<cluster> \
  --start-time '2026-04-24T14:00:00Z' --end-time '2026-04-24T16:00:00Z' \
  --period 300 --statistics Average Maximum \
  --region us-east-1
```

Cross-account metrics work via the sink — pass `--region us-east-1` and the source-account dimensions are visible automatically when the link grants `AWS::CloudWatch::Metric`.

### CloudWatch RUM (real user monitoring)

List monitors:

```bash
aws --profile shared-platform.obs rum list-app-monitors --region us-east-1 --output json
```

Monitor names follow `<env>-<appname>` convention (e.g. `prod-payment`, `uat-orders`). Each is keyed by the source domain it captures.

Get events for a window:

```bash
# RUM uses epoch MILLISECONDS and parameter names "After"/"Before"
FROM=$(($(date -u -d '2026-04-24T14:00:00Z' +%s) * 1000))
TO=$(($(date -u -d '2026-04-24T16:00:00Z' +%s) * 1000))

aws --profile shared-platform.obs rum get-app-monitor-data \
  --name <monitor-name> \
  --time-range "After=$FROM,Before=$TO" \
  --region us-east-1 \
  --max-results 100 \
  --output json
# MAX is 100 — paginate with --next-token
```

Each entry in `Events[]` is a JSON-encoded **string** (not a nested object) — parse the outer response, then JSON-parse each `Events[i]` individually.

Event types observed:
- `com.amazon.rum.page_view_event` — page navigations; check `event_details.interaction` (incremented on user clicks) and `event_details.timeOnParentPage` (ms spent on previous page)
- `com.amazon.rum.performance_resource_event` — `<link>`/`<script>`/XHR loads with `targetUrl`, `duration`, `transferSize`, `fileType`
- `com.amazon.rum.http_event` — fetch/XHR with status code
- `com.amazon.rum.xray_trace_event` — outbound traced requests (with X-Ray span data)
- `com.amazon.rum.js_error_event` — JS exceptions (filter for these when debugging client crashes)
- `com.amazon.rum.session_start_event`
- `com.amazon.rum.first_input_delay_event`, `largest_contentful_paint_event`, `cumulative_layout_shift_event` — web vitals

Filter for a specific user/session by `sessionId` (UUID, rolls after ~30 min idle) or the cookie-based `userId` (UUID, persists across sessions on the same browser). The RUM `userId` is **not** the application user — it's a browser-cookie identifier. The application user is usually encoded in URLs / JWTs and not directly indexed.

**Cross-origin iframes are not captured** by a monitor scoped to the parent origin. If a service embeds another origin's page in an iframe, the iframe's JS errors and clicks live in the iframe-origin's RUM monitor, not the parent's.

### X-Ray traces

```bash
aws --profile shared-platform.obs xray get-trace-summaries \
  --start-time '2026-04-24T14:00:00Z' --end-time '2026-04-24T16:00:00Z' \
  --filter-expression 'service("<svc>") AND error' \
  --region us-east-1
```

Or APM spans via the X-Ray Insights API for higher-level analysis. Trace IDs link logs to RUM via the `@tr` (trace ID) and `@sp` (span ID) fields most ASP.NET serilog setups emit; structured Node.js loggers typically write `trace_id` / `span_id` instead.

### CloudWatch Events / EventBridge history

For deployment markers, scaling events, or pipeline failures:

```bash
aws --profile shared-platform.obs events list-rules --region us-east-1
aws --profile shared-platform.obs cloudtrail lookup-events \
  --start-time ... --end-time ...
```

CloudTrail is per-account; from Shared-Platform you can only see actions in 613437596725 itself. Linked accounts have their own trails.

## Behavior Rules

1. **Authentication is automatic — never ask the user to log in.** Run the bootstrap flow from the "Authentication" section yourself: probe `aws --profile shared-platform.obs sts get-caller-identity`, create the profile with `aws-sso-util configure profile` if missing, and run `aws sso login --profile <any-sso-profile>` if the SSO session is stale. Only the `aws sso login` step opens a browser; everything else runs unattended.
2. **Default account is 613437596725 / ObservabilityReadOnlyAccess** unless the user explicitly asks for another account. That role only grants observability reads — write actions will be denied even with valid creds.
3. **Default region is `us-east-1`**. Other regions exist (us-east-2, us-west-2) but are usually sparse.
4. **Default environment is `prod`** when the user doesn't specify one. State explicitly in the response which environment you queried (e.g. "querying `/ecs/prod-orders-app`") so a wrong default is easy to spot. Fall back to qa/uat/sb only when the user names them or prod is genuinely empty/unavailable.
5. **Default time range is `now - 1 hour`**. Widen only when asked or empty.
6. **Confirm retention before claiming "logs are gone"** — `describe-log-groups` returns `retentionInDays` per group. Re-check if the user's target date is older than the retention.
7. **Use `--log-group-identifiers` without trailing `:*`** — the policy-syntax wildcard suffix is rejected by `start-query`. Same for `--log-group-identifier` on `filter-log-events`.
8. **Start small** — `--max-results 100` is the hard limit for RUM; for Logs Insights use `limit N` in the query string.
9. **Aggregate before listing** — for "find error types" / "top N" questions, use `stats count() by ...` in the query string. Pulling raw events first wastes scanned-byte quota and drowns rare errors.
10. **Save large API responses to a temp file** and parse them with a script/tool, not inline pipes — some shells (notably PowerShell) drop bytes when the AWS CLI's JSON streaming meets a `ConvertFrom-Json` pipe with stderr in the mix.
11. **Never log full SSO access tokens or session credentials.** Show at most the first 4 characters when verifying env vars are set.
12. **Run parallel queries** when fetching samples for multiple log groups / monitors — each `aws` invocation is independent.
13. **Use the managed `shared-platform.obs` profile** — `aws-sso-util` writes a `credential_process` entry to `~/.aws/config` that the CLI refreshes on its own. This is the path that runs unattended; do not write profiles by hand.
14. **Cross-origin iframes**: when debugging a flow that spans multiple origins, query each origin's RUM monitor separately. A single monitor only sees its own origin's events.
15. **Time unit gotchas**: Logs APIs use epoch **seconds** for `start-query` and **milliseconds** for `filter-log-events`; RUM API uses epoch **milliseconds**; ISO-8601 strings work for `cloudwatch get-metric-statistics` and `xray`. Double-check before debugging "empty results".
16. **Pagination is mandatory** for any cross-account log-group listing or RUM event scan — there's typically more than a single batch even in narrow time windows.

## Common gotchas

- **Logs Insights field `@log`** returns the log group ARN; useful for grouping results across accounts in one query.
- **`@message like /<regex>/`** uses Java regex, not Logs Insights' own glob. Escape forward slashes properly.
- **`filter @message like /substr/`** matches the **raw JSON string** of the log event — so `"foo":"bar"` and `"foo": "bar"` need different patterns. Search for the exact substring as it appears in the JSON.
- **RUM `userId` is browser-scoped**: two different real users on the same machine share it; the same real user on different browsers gets different `userId`s. Use it for "same browser came back later" detection, not for "is this user X".
- **Cross-account `aws s3` is gated separately** from the observability sink. Listing S3 buckets via this role typically fails with `AccessDenied` — that's expected.
- **The `prod-*` RUM monitor list** does not include every service that ships RUM data; some services only ship to Datadog. If a monitor is missing, the data isn't in CloudWatch RUM.
- **`describe-log-groups --log-group-name-prefix`** is exact-prefix, not glob. `/ecs/prod-` matches `/ecs/prod-foo` but not `/ecs/foo-prod`. Use `--log-group-name-pattern` for substring matches.
- **Quoting Logs Insights queries on the command line** is fragile across shells (backticks, `$`, `|`, regex slashes). Always write the query to a file and pass `--query-string file://...` — it works the same on bash, zsh, PowerShell, and cmd.
