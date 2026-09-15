---
type: repo-memory
team: CBS
repos:
  - stop-job-postings-lambda
source: "C:\JT Repositories\stop-job-postings-lambda\CLAUDE.md"
captured: 2026-09-15
sha256_short: 8fcfdbbd7502
updated: 2026-09-15
---

# stop-job-postings-lambda — repo memory

> **Snapshot, not the source.** The live file is `C:\JT Repositories\stop-job-postings-lambda\CLAUDE.md` — that is what Claude Code actually loads in the repo. This is a read-only copy captured 2026-09-15 (53 lines, sha256 `8fcfdbbd7502`) so the vault can answer questions about repo conventions without opening the repo.
> Edit the repo's file, then re-import. Never edit this copy and expect it to take effect.
>
> Below this line is the repo's own content, verbatim. Per [coding-standards](../../protocols/coding-standards.md), a repo's conventions win inside that repo — so vault [wiki voice](../../protocols/wiki-voice.md) does **not** apply to it and it has not been rewritten.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

An AWS Lambda that stops all active job postings when a job is closed. The Lambda is SQS-triggered: an SNS topic (`JobNotification`, published by Core) fans out `Job.Status === "Closed"` messages to the Lambda's SQS queue (the SNS subscription applies a `filter_policy` so only Closed events arrive). The handler then calls the Core API v2 to enumerate and delete (stop) every posting for that job.

The repo has two independent halves:
- `lambda/` — the TypeScript handler + Jest tests.
- `infra/` — Terraform for the Lambda, SQS queue + DLQ, SNS subscription, IAM, security group, and CloudWatch log group.

## Commands

All Node commands run from `lambda/`:

```bash
cd lambda
npm run build          # tsc -> dist/ (prebuild wipes dist via rimraf)
npm test               # jest (all tests)
npx jest tests/index.test.ts              # single test file
npx jest -t "more than 100"               # single test by name
npm run package        # build + copy package.json to dist/ + npm i --omit=dev (packages for deploy)
```

`npm run package` runs `build-scripts/package.sh` (bash). On Windows, `build-scripts/package.ps1` is the PowerShell equivalent. Terraform zips `lambda/dist/` directly (`data.archive_file` in `infra/main.tf`), so `dist/` must contain the built handler **and** its production `node_modules` before `terraform apply`.

Terraform (from `infra/`) uses an HTTP backend on GitLab and requires vars: `env` (sb|qa|uat|prod), `profile_name`, `gitlab_username`, `gitlab_access_token`, plus the three `*_remote_state_address` vars and `commit_sha`.

## Handler flow (`lambda/src/index.ts`)

1. Parse the SQS record: `body` → `Message` (SNS envelope) → `Job`. Extract `Status`, `PartnerId`, `CompanyId`, `Id`.
2. Resolve `channelSiteId` from `partnerId` (used only for log enrichment).
3. Only act when `status === "Closed"`.
4. `getPostingsCount(jobId)`; if 0/undefined, log and return.
5. If count > 99: paginate `getPostings` at 99/page and stop each posting. Otherwise fetch all in one call and stop each.
6. Errors are caught and logged — the handler never rethrows, so a message is not retried by SQS on application errors (only the DLQ redrive on repeated failures/timeouts applies, `maxReceiveCount = 4`).

## Services

- `services/coreApiService.ts` — thin `axios` wrapper over Core API v2 (`/api/v2/job/{id}/posting`, `.../count`, `/api/v2/partner/{id}/channelsite`, `DELETE /api/v2/posting/{id}`). Base URL comes from the `CORE_API` env var. A commented-out v1 `stopPosting` variant is retained for reference.
- `services/loggingService.ts` — Winston JSON logger. The `winston.createLogger` instance is hoisted to **module scope** on purpose: the OTel/AppSignals auto-instrumentation hook must patch Winston only once per container cold start. Do not move logger creation back into the class constructor.
- `utils/logJson.ts` — for code paths that use bare `console.*` instead of Winston; emits a single JSON line with `otel_trace_id`/`otel_span_id` from the active OTel span so AppSignals log correlation works. AppSignals patches Winston and `console.log(JSON.stringify(...))` but not `console.log("str", obj)`.

## Observability (AppSignals / OpenTelemetry)

The Lambda runs the CloudWatch Application Signals Node.js distro layer (`AWSOpenTelemetryDistroJs`) via `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument`. Key env in `infra/main.tf`: `OTEL_NODE_DISABLED_INSTRUMENTATIONS=none` is deliberate — the distro enables only http+aws-sdk by default, and setting `none` turns on the Winston instrumentation that injects trace context into logs. `@opentelemetry/api` is a **runtime** dependency (not devDependency) because `logJson` imports it at runtime. This setup replaced a prior Datadog Extension layer; see the `moved` block in `main.tf` documenting the state migration from the `DataDog/lambda-datadog/aws` module.

## Notes / gotchas

- IDs arrive as **numbers** in the SQS payload (`Job.Id`, `PartnerId`), not strings — tests assert calls like `getPostingsCount(789)` with numeric args, despite the `Posting`/`ChannelSite` TS interfaces typing id fields as `string`.
- Only `event.Records[0]` is processed; the Lambda assumes one record per invocation.
- `getPostings` uses `omitInactivePostings=true`, so only active postings are fetched and stopped.
