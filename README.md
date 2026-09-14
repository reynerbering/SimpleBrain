# My Second Brain

I dump raw stuff into `/raw`. AI turns it into clean notes in `/wiki`. That's it.

## Folders

- `/raw` — anything I capture: notes, PDFs, screenshots, links
- `/wiki` — clean notes written by AI
- `/archive` — processed `/raw` files land here so I can see what's been handled
- `/coding` — engineering notes and reusable orchestration prompts
- `/prompts` — standing prompts run against the vault
- `/tickets` — one file per Jira ticket
- `/skills` — versioned source of truth for my Claude Code skills

## The Loop

1. Write or drop anything into `/raw`.
2. Run an AI agent with the prompt in `prompts/translate.md`.
3. Read the updated `/wiki`.

The whole folder is a git repo, so nothing is ever lost.

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

**The `repos:` property uses the local folder name, exactly as it appears on disk.** Lowercase, hyphenated, no GitLab path. That keeps it greppable and unambiguous.

### CBS — Core Business Services (Jira key: `CBS`)

| Local folder | GitLab path |
| --- | --- |
| `CoreAPI` | _not recorded_ |
| `close-job-lambda` | _not recorded_ |
| `ea-distribution-update` | _not recorded_ |
| `stop-job-postings-lambda` | _not recorded_ |
| `call-distribution-update-lambda` | _not recorded_ |

### AS — Apply Systems (Jira key: `AS`)

| Local folder | Name | GitLab path |
| --- | --- | --- |
| `clickapply` | ClickApply | `jobtarget/apps/clickapply` |
| `hosted-apply` | Hosted Apply | `jobtarget/apps/hosted-apply` |
| `cloud-lookup-api` | Posting Reference Lookup API | `jobtarget/apps/apply-systems/cloud-lookup-api` |
| `apply-with-jobtarget-api` | Apply With JobTarget API | `jobtarget/apps/apply-systems/apply-with-jobtarget-api` |
| `apply-with-jobtarget-widget` | Apply With JobTarget Widget | `jobtarget/apps/apply-systems/apply-with-jobtarget-widget` |
| `apply-with-jobtarget-config-ui` | Apply With JobTarget Config UI | `jobtarget/apps/apply-systems/apply-with-jobtarget-config-ui` |
| `recruitsite-02` | RecruitSite 2.0 | `jobtarget/marketing/recruitsite-02` |
| `recruitsite-02-configuration-app` | RecruitSite 2.0 Configuration App | `jobtarget/marketing/recruitsite-02-configuration-app` |
| `recruit-site-job-notification-lambda` | Recruit Site Job Notification Lambda | `jobtarget/marketing/recruit-site-job-notification-lambda` |
| `jobapplicationapi` | JobApplicationAPI | `jobtarget/core-systems/applications/jobapplicationapi` |
| `analytics-api` | analytics-api | `jobtarget/apps/apply-systems/analytics-api` |
| `questionnaire-api` | Questionnaire Api | `jobtarget/apps/apply-systems/questionnaire-api` |
| `disposition-formatter-lambda` | Disposition Formatter Lambda | `jobtarget/apps/apply-systems/disposition-formatter-lambda` |
| `disposition-transmitter-lambda` | Disposition Transmitter Lambda | `jobtarget/apps/apply-systems/disposition-transmitter-lambda` |
| `disposition-listener-lambda` | Disposition Listener Lambda | `jobtarget/apps/apply-systems/disposition-listener-lambda` |
| `enrichment-manager-lambda` | Enrichment Manager Lambda | `jobtarget/apps/apply-systems/enrichment-manager-lambda` |
| `delivery-manager-lambda` | Delivery Manager Lambda | `jobtarget/apps/apply-systems/delivery-manager-lambda` |
| `verification-manager-lambda` | Verification Manager Lambda | `jobtarget/apps/apply-systems/verification-manager-lambda` |
| `interview-reminder-email` | Interview Reminder Email | `jobtarget/apps/apply-systems/interview-reminder-email` |

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
