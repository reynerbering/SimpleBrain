## Folders

- `/raw` — anything I capture: notes, PDFs, screenshots, links
- `/wiki` — clean notes written by AI
- `/archive` — processed `/raw` files land here so I can see what's been handled
- `/coding` — engineering notes and reusable orchestration prompts
- `/prompts` — standing prompts run against the vault
- `/tickets` — one file per Jira ticket
- `/skills` — versioned source of truth for my Claude Code skills

## The Workflow

How coding work actually gets done. Two phases, in order. Phase 1 decides, Phase 2 builds — and they never blur together.

### Phase 1 — Grill it until it's decided

Nothing gets implemented before the thinking is finished.

1. **Start from the work.** Pull the ticket detail from Jira, or start from a raw idea that just showed up.
2. **Grill it.** Run one of the Matt Pocock grilling skills:
   - `/grill-me` — the standard relentless interview over a plan or design.
   - `/grill-with-docs` — same interview, but also produces ADRs and a glossary as it goes, via `/domain-modeling`. Use this when the work introduces new domain vocabulary.
   - `/grilling` — the underlying skill both of the above run.
3. **Answer one question at a time.** The skill walks the decision tree branch by branch and waits. Facts it looks up itself; the decisions are mine.
4. **Land on a shared understanding.** The output is one big document that the agent and I actually agreed on — not a summary it wrote at me.
5. **File it.** That document becomes `/wiki/<KEY>-<slug>.md`. See the design doc protocol in [CLAUDE.md](CLAUDE.md).

### Phase 2 — Ship it through the pipeline

The agreed document is the input. Now it gets built.

1. **Branch for the ticket** — `feat/PROJ-1234-<slug>`. Never on `main`.
2. **Run `/ship`** — the four-agent pipeline: Planner → Coder → Tester → Reviewer. See [coding/four-agent-pipeline.md](coding/four-agent-pipeline.md).
3. **Feed the Planner the design doc**, not a one-line ask. Phase 1 exists so the spec starts from settled decisions.
4. **Read `.pipeline/review.md` first**, then the diff. The pipeline never merges — I'm the final gate.
5. **Fold the outcome back in.** Anything the pipeline changed, flagged, or forced a rethink on goes back into the same wiki doc as a dated revision.

### Where things end up

| Artifact | Lives in | Holds |
| --- | --- | --- |
| Design doc | `/wiki/<KEY>-<slug>.md` | Every decision + reasoning, before and after implementation |
| Ticket log | `/tickets/<KEY>.md` | Dated activity: what was done, what was touched, pipeline verdict, blockers |
| Pipeline handoffs | `.pipeline/` in the repo | Scratch. Gitignored. Not a record. |

The wiki doc owns the **decisions**. The ticket owns the **log**. They link to each other and neither repeats the other.

## Repos

All checked out under `C:\JT Repositories`. Two teams, two Jira projects.

**Jira keys are the source of truth for ticket and design-doc filenames** — `CBS-1234.md`, `AS-5678.md`. Never write `APPSYS-*`; that key does not exist in Jira.

**The `repos:` property uses the local folder name, exactly as on disk.** Lowercase, hyphenated, no GitLab path.

GitLab paths below were read from each repo's `git config remote.origin.url` on 2026-09-15. Tech stacks were read from manifests on disk. Neither was guessed.

**Type** is one of four values — API and Lambda alone did not cover the set:

- **API** — an HTTP service. Deployed as a container or long-running process.
- **Lambda** — an event-driven AWS function. No HTTP surface of its own.
- **Web app** — server-rendered UI. `hosted-apply` has 26 page templates; the Laravel pair render Blade views.
- **Frontend** — browser-side only. The two Stencil repos ship web components, not a server.

Assigned on evidence: presence of `swagger.json`, count of non-error view templates, Lambda packaging (Terraform / SAM / Serverless), and project SDK type.

### CBS — Core Business Services (Jira key: `CBS`)

Note: these five are **not** in one GitLab group. They span `platform/core-api` and two `core-systems` subgroups.

| Local folder | Name | Type | GitLab path | Tech stack |
| --- | --- | --- | --- | --- |
| `CoreAPI` | Core API | **API** | `jobtarget/platform/core-api/CoreAPI` | .NET 6 · ASP.NET Core web API · EF Core + MSSQL/DynamoDB/Redis · NUnit · Docker · 13 projects |
| `close-job-lambda` | Close Job Lambda | **Lambda** | `jobtarget/core-systems/jobs-domain/close-job-lambda` | Node 20 · TypeScript · AWS Lambda · Terraform · Jest |
| `ea-distribution-update` | EA Distribution Update | **Lambda** | `jobtarget/platform/core-api/ea-distribution-update` | Node 24 · TypeScript · AWS Lambda · AWS SAM · Jest |
| `stop-job-postings-lambda` | Stop Job Postings Lambda | **Lambda** | `jobtarget/core-systems/postingdomain/stop-job-postings-lambda` | Node 24 · TypeScript · AWS Lambda · Terraform · Jest |
| `call-distribution-update-lambda` | Call Distribution Update Lambda | **Lambda** | `jobtarget/platform/core-api/call-distribution-update-lambda` | Node 18 · TypeScript · AWS Lambda · Serverless Framework · **no tests** |

### AS — Apply Systems (Jira key: `AS`)

All 19 remotes verified against the expected paths — every one matched.

| Local folder | Name | Type | GitLab path | Tech stack |
| --- | --- | --- | --- | --- |
| `clickapply` | ClickApply | **API** | `jobtarget/apps/clickapply` | Node 24 · **Sails.js 1.5** · JS · Mocha · Docker |
| `hosted-apply` | Hosted Apply | **Web app** | `jobtarget/apps/hosted-apply` | Node 20+ · **Sails.js 1.5** · JS · Mocha + nyc · Docker · pm2 · has own `CLAUDE.md` |
| `cloud-lookup-api` | Posting Reference Lookup API | **API** | `jobtarget/apps/apply-systems/cloud-lookup-api` | Node 16 · **Sails.js 1.5** · JS · Mocha · Docker |
| `apply-with-jobtarget-api` | Apply With JobTarget API | **API** | `jobtarget/apps/apply-systems/apply-with-jobtarget-api` | Node 18 · **Sails.js 1.5** · JS · Mocha · Docker |
| `apply-with-jobtarget-widget` | Apply With JobTarget Widget | **Frontend** | `jobtarget/apps/apply-systems/apply-with-jobtarget-widget` | TypeScript 5 · **Stencil 4** web components · Jest |
| `apply-with-jobtarget-config-ui` | Apply With JobTarget Config UI | **Frontend** | `jobtarget/apps/apply-systems/apply-with-jobtarget-config-ui` | TypeScript · **Stencil 2** SPA · Jest · Docker/nginx |
| `recruitsite-02` | RecruitSite 2.0 | **Web app** | `jobtarget/marketing/recruitsite-02` | **PHP 8 · Laravel 9** · Livewire 2 · Vite + Tailwind + Alpine · PHPUnit · Docker · has own `CLAUDE.md` |
| `recruitsite-02-configuration-app` | RecruitSite 2.0 Configuration App | **Web app** | `jobtarget/marketing/recruitsite-02-configuration-app` | **PHP 8.1 · Laravel 9** · Livewire 2 · Vite + Tailwind · PHPUnit · Docker |
| `recruit-site-job-notification-lambda` | Recruit Site Job Notification Lambda | **Lambda** | `jobtarget/marketing/recruit-site-job-notification-lambda` | **.NET 8** · AWS Lambda (SQS-triggered) · Serverless Framework · xUnit |
| `jobapplicationapi` | JobApplicationAPI | **API** | `jobtarget/core-systems/applications/jobapplicationapi` | TypeScript 5 · **Express + tsoa** · Jest · Docker · no lockfile committed |
| `analytics-api` | analytics-api | **API** | `jobtarget/apps/apply-systems/analytics-api` | **.NET 10** · ASP.NET Core API · MongoDB · Docker · **no tests** |
| `questionnaire-api` | Questionnaire Api | **API** | `jobtarget/apps/apply-systems/questionnaire-api` | **.NET 8** · ASP.NET Core API · MSSQL · Docker · preview packages · **no tests** |
| `disposition-formatter-lambda` | Disposition Formatter Lambda | **Lambda** | `jobtarget/apps/apply-systems/disposition-formatter-lambda` | Node 22 · JS · AWS Lambda · Terraform · EventBridge · **no tests** |
| `disposition-transmitter-lambda` | Disposition Transmitter Lambda | **Lambda** | `jobtarget/apps/apply-systems/disposition-transmitter-lambda` | Node 22 · JS · AWS Lambda · Terraform · GraphQL · **no tests** |
| `disposition-listener-lambda` | Disposition Listener Lambda | **Lambda** | `jobtarget/apps/apply-systems/disposition-listener-lambda` | Node 22 · JS · AWS Lambda · Terraform · **no lockfile** · **no tests** |
| `enrichment-manager-lambda` | Enrichment Manager Lambda | **Lambda** | `jobtarget/apps/apply-systems/enrichment-manager-lambda` | Node 22 · JS · AWS Lambda · Terraform · aws-sdk **v2** · **no tests** |
| `delivery-manager-lambda` | Delivery Manager Lambda | **Lambda** | `jobtarget/apps/apply-systems/delivery-manager-lambda` | Node 22 · JS · AWS Lambda · Terraform · MongoDB · **no tests** |
| `verification-manager-lambda` | Verification Manager Lambda | **Lambda** | `jobtarget/apps/apply-systems/verification-manager-lambda` | Node 22 · JS · AWS Lambda · Terraform · aws-sdk **v2** · **no tests** |
| `interview-reminder-email` | Interview Reminder Email | **Lambda** | `jobtarget/apps/apply-systems/interview-reminder-email` | Node 22 · JS · AWS Lambda · Terraform · aws-sdk **v2** · **no tests** |

### Test readiness — read before any pipeline run

Verified by inspection on 2026-09-15. This is the single biggest constraint on Phase 2.

- **11 of the 24 repos have no test files at all.** All 7 Apply Systems Lambdas, both .NET Apply Systems APIs (`analytics-api`, `questionnaire-api`), and `call-distribution-update-lambda`.
- **Three declared test commands point at files that do not exist.** `test:unit` runs `jest --config test-unit.js` in the three disposition Lambdas; `npm test` runs `node test-local.js` in `enrichment-manager-lambda` and `delivery-manager-lambda`. They fail on invocation, not on a real assertion.
- **`verification-manager-lambda` has no `test` script at all**, and its `package.json` is still named `lambda-hello-world`.
- **A bare `jest` with no matching files exits non-zero.** Four Lambdas install Jest with nothing to run — that reads as a red suite, not a green one.
- **`cloud-lookup-api` runs a single spec** on `npm test` even though `test/` holds more. A green there covers almost nothing.

**Consequence:** for those repos the first pipeline run cannot start at the Tester stage — there is no suite to run. Write the first real test by hand before letting `/ship` near them.

Repos with a genuine suite today: `CoreAPI` (NUnit), the three CBS TypeScript Lambdas (Jest), the four Sails apps (Mocha), both Stencil apps (Jest), the Laravel pair (PHPUnit), `recruit-site-job-notification-lambda` (xUnit), and `jobapplicationapi` (Jest).

### Unassigned

`C:\JT Repositories` holds 50 repos; the 24 above are the ones I actively own. The rest are checked out but **not assigned to a team here** — do not assume CBS or AS for them without asking:

`analytics-aggregator`, `applyagent`, `atsapi-v6`, `auth-api`, `core-api-advisor`, `description-enrichment-lambda`, `descriptionenrichmentauditlambda`, `devtoolkit`, `easy-apply-connector`, `eventprocessorlambda`, `jobs-domain-management-app`, `jobsapi`, `jobseeker-module`, `jt-job-manager-api`, `lambda`, `mcp-servers`, `partner-api`, `partner-event-receiver-lambdas`, `partnermarketplaceapi`, `payments-markorderaspayed`, `posting-distribution-update-v2`, `postingdistributionupdate`, `recruitsite-config-self-configuration-lambda`, `release-notes-generator`, `template-api`, `zzz-anti`

## Stacks

What I work in. The `ship-tester` uses this shape to know how to run a suite — see [coding/four-agent-pipeline.md](coding/four-agent-pipeline.md).

**Resolution order.** A repo's own `CLAUDE.md` always wins. This is the fallback when a repo doesn't have one.

### C# / .NET

- Detect: `.sln` or `.csproj`
- Test: `dotnet test`
- Framework: match whatever the repo already uses — xUnit, NUnit, or MSTest. Never introduce a second one.

<!-- Fill in as they get decided: default target framework, solution layout conventions, anything non-obvious about running tests locally. -->

### Node / TypeScript

- Detect: `package.json`
- Test: the `test` script in `package.json`
- Package manager: from the lockfile. Never switch.

<!-- Fill in as they get decided: preferred runner (Jest/Vitest), monorepo tooling, default package manager for new repos. -->

### Per-repo overrides

If a repo needs something other than the above, put it in **that repo's `CLAUDE.md`**, not here. It travels with the code and works for teammates too.

```markdown
## Commands
- Test: <exact command>
- Build: <exact command>
- Lint: <exact command>
```
