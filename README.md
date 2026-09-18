# SimpleBrain

A personal second brain: raw capture in, clean notes and shipped tickets out.

**The rules live in [`/protocols`](protocols/)** — one file per topic, each the single source of truth for it. [`CLAUDE.md`](CLAUDE.md) imports the ones that travel to code repos and links the rest. This file is an index plus the one thing that lives nowhere else: the **repo inventory** below.

## Protocols

| Protocol | Owns | Scope |
| --- | --- | --- |
| [workflow.md](protocols/workflow.md) | The two-phase workflow, Phase 1 and Phase 2 steps, **branch and worktree naming**, **where work lives** (`/in-progress` → `/later` → `/wiki`) and the "finish it later" handoff, where each artifact ends up | travels |
| [design-docs.md](protocols/design-docs.md) | Design doc location, division of labour with tickets, how to write one | travels |
| [tickets.md](protocols/tickets.md) | Ticket file location, entry shape, sourcing from Jira, pipeline logging | travels |
| [frontmatter.md](protocols/frontmatter.md) | The property contract and the Bases that consume it | travels |
| [coding-standards.md](protocols/coding-standards.md) | Stacks, resolution order, per-repo pinned test commands | travels |
| [databases.md](protocols/databases.md) | Which DB MCP server belongs to which project, environments, write safety | travels |
| [repo-memory.md](protocols/repo-memory.md) | Where repo CLAUDE.md content lives, and which way it is imported | travels |
| [wiki-voice.md](protocols/wiki-voice.md) | How anything written into the vault should read | travels |
| [vault-map.md](protocols/vault-map.md) | The folder model and what each root file owns | vault-only |
| [skills.md](protocols/skills.md) | Where the skills come from, and the three installers | vault-only |

"Travels" means the rule applies in every repo and is `@import`ed into every session. "Vault-only" means it governs this vault and should not be applied inside a code repo.

**Naming**, at a glance — the rules themselves live in
[workflow.md](protocols/workflow.md#branch-and-worktree-naming); this is a pointer, not a copy:

| Artifact | Pattern |
| --- | --- |
| Design doc | `<JIRA-KEY>-<slug>.md`, in `/in-progress/<TEAM>/`, `/later/` or `/wiki/<TEAM>/` |
| Ticket log | `tickets/<TEAM>/<JIRA-KEY>.md` |
| Branch | `<JIRA-KEY>-<slug>` — no `feat/` prefix |
| Isolated worktree | `<repo-folder>-<JIRA-KEY>`, beside the repo |

The `<slug>` is the same string in all of them, so one search finds the doc, the branch and the
worktree.

**Also single-source, elsewhere:**

- [`coding/four-agent-pipeline.md`](coding/four-agent-pipeline.md) — the `/ship` pipeline: stages, models, gates, handoff files.
- [`templates/design-doc.md`](templates/design-doc.md) and [`templates/ticket.md`](templates/ticket.md) — the templates themselves.

## One fact, one home

Every fact lives in exactly one file. If it is needed somewhere else, it gets linked or imported — never copied. The same fact in two places is a bug: delete one, link to the other.

## Repos

All checked out under `C:\JT Repositories`. Two teams, two Jira projects.

Jira key rules are in [protocols/tickets.md](protocols/tickets.md). The `repos:` property rule is in [protocols/frontmatter.md](protocols/frontmatter.md). This section is the inventory itself — nothing else.

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
| `CoreAPI` | Core API | **API** | `jobtarget/platform/core-api/CoreAPI` | .NET 10 · ASP.NET Core web API · EF Core 10 + MSSQL/DynamoDB/Redis · NUnit · Docker · 13 projects |
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

Repos with a genuine suite today: `CoreAPI` (NUnit, **two projects** — see the pinned commands in [protocols/coding-standards.md](protocols/coding-standards.md)), the three CBS TypeScript Lambdas (Jest), the four Sails apps (Mocha), both Stencil apps (Jest), the Laravel pair (PHPUnit), `recruit-site-job-notification-lambda` (xUnit), and `jobapplicationapi` (Jest).

⚠️ **A suite existing is not the same as a suite being runnable.** `CoreAPI`'s legacy project needs a seeded local container whose schema is not managed by the repo, so it can be red for reasons that have nothing to do with the code. Read its notes in [protocols/coding-standards.md](protocols/coding-standards.md) before reading a red run there as a real failure.

### Unassigned

`C:\JT Repositories` holds 50 repos; the 24 above are the ones I actively own. The rest are checked out but **not assigned to a team here** — do not assume CBS or AS for them without asking:

`analytics-aggregator`, `applyagent`, `atsapi-v6`, `auth-api`, `core-api-advisor`, `description-enrichment-lambda`, `descriptionenrichmentauditlambda`, `devtoolkit`, `easy-apply-connector`, `eventprocessorlambda`, `jobs-domain-management-app`, `jobsapi`, `jobseeker-module`, `jt-job-manager-api`, `lambda`, `mcp-servers`, `partner-api`, `partner-event-receiver-lambdas`, `partnermarketplaceapi`, `payments-markorderaspayed`, `posting-distribution-update-v2`, `postingdistributionupdate`, `recruitsite-config-self-configuration-lambda`, `release-notes-generator`, `template-api`, `zzz-anti`

