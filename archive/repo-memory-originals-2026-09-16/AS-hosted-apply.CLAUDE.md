# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**RecruitSites 2.0 / Hosted Apply** — a [Sails.js](https://sailsjs.com) 1.x application (internally `recruit-sites-v-2`) that renders public job landing pages and handles job applications. Given a job/posting hash it fetches job data from internal JobTarget APIs, renders an apply page, accepts the application (resume upload + custom questions), persists it to MongoDB, and fans it out downstream (analytics service + AWS EventBridge). Runs on Node `^20.19.0 || >=22.12.0`.

> The `README.md` is **stale**: it describes a `docker-compose` workflow and a Grunt/Node-12 stack that no longer exist. Follow this file instead.

## Commands

Local dev is plain Node + npm (no docker-compose file is checked in). First-time setup:

```bash
cp .env.example .env      # then fill in secrets marked <REQUEST FROM TEAM>
npm install
```

- **Run the app:** `node app.js` (lifts Sails; dev defaults to port **1337**, `sails_custom__baseUrl`). `npm start` runs it with `NODE_ENV=production`. In prod, OpenTelemetry is wired via `NODE_OPTIONS` in `release.Dockerfile`, not by the app itself.
- **Build assets:** `npm run build:assets` (`scripts/build-assets.js`) runs the Shipwright/rsbuild **production** build to `.tmp/public` outside of a lift, then asserts the manifest has an `app` entry — the same contract `config/bootstrap.js` checks. The hook swallows build errors (it logs `Build failed` and returns normally), so this is the only way to make a broken asset bundle exit non-zero; use it as a CI/pre-commit gate and as a `RUN` step in `release.Dockerfile`. Scope, precisely: this is a **production-path** tool. It does not speed up `node app.js`, because in development the hook ignores `.tmp/public` and serves from an in-memory rsbuild dev server (`dev.writeToDisk` is limited to `manifest.json`) — and that dev server **clears `.tmp/public` on startup**, so a dev lift deletes whatever this produced. It also does not stop the production container from rebuilding at boot: the hook builds unconditionally from `initialize()` regardless of what is already on disk.
- **Lint:** `npm run lint` (auto-fix: `npm run lint:fix`). ESLint **v9 pinned to legacy config** via `ESLINT_USE_FLAT_CONFIG=false` reading `.eslintrc`; lints `api config routes utils app.js`, `--max-warnings=0` (zero tolerance). `npm run lint:assets` covers `assets/`.
- **Unit tests:** `npm run test:unit` — Mocha over `test/unit/**/*.spec.js`. Fast; **does not lift Sails** (see Testing).
- **Integration tests:** `npm run test:integration` — Mocha over `test/integration/**`, loads `test/lifecycle.spec.js` first, which **lifts Sails** (`NODE_ENV=test`).
- **Coverage:** `npm run test:coverage` — `nyc` with **enforced thresholds** (`.nycrc.json`: lines/statements 65, functions 80, branches 50). Coverage-gated CI will fail below these.
- **Full check:** `npm test` = lint + unit + custom-tests.
- **Run a single test file:** `npx cross-env NODE_ENV=test mocha path/to/file.spec.js` (add `--config .mocharc.integration.js` if it needs a lifted Sails). Use a single test's name with `-g "<pattern>"`.

Env vars are set via `cross-env` in npm scripts (Windows-friendly) — invoke through the npm scripts rather than bare `mocha`/`eslint` so `NODE_ENV`/`ESLINT_USE_FLAT_CONFIG` are set.

## Architecture

### Configuration model
All runtime config comes from **environment variables** using Sails' convention `sails_<section>__<key>` (double underscore) → `sails.config.<section>.<key>`. `.env.example` is the authoritative list of every knob (upstream service URLs, SendGrid, Redis, MongoDB, reCAPTCHA, Optimizely, EventBridge bus, encryption key). `config/custom.js` reads a few `process.env` values with dev fallbacks; `config/env/{development,production,test}.js` hold per-env overrides. Secrets are **not** in the repo — get `.env` values from the team.

### Request flow (core apply path)
1. **Routes** (`config/routes.js`) map `/job/:hash` and `/jobs/:hash` to `JobController`. `jobs` vs `job` matters — the `jobs` path additionally fires click-tracking to the analytics service.
2. **`JobController.getJobDetails`** → **`sails.helpers.api`** (`api/helpers/api.js`) is the central fetch helper: decodes the hash via `sails.helpers.idLookup` (falls back to `sails.hashids.decode`) into `[jobId, postingId, siteId/mediaId, recruiterId]`, checks **Redis** (prefix `hosted_apply_`), on miss calls `coreApiUrl` + `analyticsUrl` for job data and custom questions, caches, and returns everything through a `callback(locals)`. Job data is normalized via `sails.helpers.transformJobData`.
3. **`JobController.apply`** (POST) validates (`sails.helpers.validation`, reCAPTCHA via `api/utils/recaptcha.js`), stores an `Application`, encrypts the id for the redirect (`sails.helpers.encrypt`), forwards it (`sails.helpers.sendApplication`), and emits a `partialApplication` EventBridge event (`sails.helpers.emitterService`).
4. Rendered via EJS views in `views/pages/`.

### Where logic lives
- **Sails helpers** (`api/helpers/`) hold most business logic, invoked as `sails.helpers.<camelCasedFileName>(...)`. Key ones: `api` (job fetch/cache), `send-application`, `emitter-service` (EventBridge; **strips PII** — name/email/phone/resume/coverLetter/questions — before emitting), `transform-job-data`, `get-suggested-jobs` + `create-suggested-posting-reference` (thank-you-page suggested jobs), `send-verification-email`, `encrypt`/`decrypt`, `resume-parser`, `validation`, `email*` (SendGrid follow-ups).
- **Two `utils` locations** (both linted): root **`utils/crypto-utils.js`** (AES-256-CBC using `sails_applicant_ENCRYPTION_KEY`, read at import-time) and **`api/utils/recaptcha.js`** (site-key reCAPTCHA + `?nocaptcha=1&token=` bypass in non-prod).
- **`config/bootstrap.js`** runs before lift and is critical:
  - Attaches third-party clients as **globals on `sails`** — `sails.request` (request-promise), `sails.urllib`, `sails.hashids`, `sails.redis`, `sails.sendgrid`, `sails.optimizely`, `sails.dataTeamAwsClient` (EventBridge, default AWS credential chain), `sails.uuid`, `sails.pdfDocument` (PDFKit), `sails.logger` (Winston → Console + OpenTelemetry transport).
  - **In `NODE_ENV=test`** installs no-op shims for `sails.redis` and `sails.optimizely` so a test lift opens no network connections (integration tests replace them with sinon stubs).
  - **In `production`** asserts the Shipwright asset build produced a valid `.tmp/public/manifest.json` (with an `app` entry) and **throws to abort lift** if not — because `sails-hook-shipwright` swallows build errors and would otherwise boot an unstyled app that still passes health checks.

### Feature areas beyond core apply
- **Applicant verification** — routes `GET /verify/:token`, `POST /api/verify/submit`, etc. (`config/routes.js`); controllers under `api/controllers/applicant/`; models `ApplicantVerification` + `VerificationAnswer`; token crypto in `utils/crypto-utils.js`; questions in `api/config/verification-questions.js`. `routes/verification.js` is an empty placeholder.
- **Suggested jobs** — lazy-loaded by the thank-you page (`GET /api/v1/application/suggested-jobs`), click creates a posting reference (`POST .../suggested-job-redirect`). Gated by `sails_custom__isSuggestedJobsEnabled`.
- **Health / sitemap** — `GET /health`, `/health/dependencies` (`HealthCheckController`); `SitemapController`/`SitemapService` generate and submit sitemaps (S3-hosted).

### Data layer
- **MongoDB** via `sails-mongo` (`mongodb` 6.x driver). Datastore URL from `sails_datastores__default__url`. `config/models.js` sets `migrate: 'safe'`, `id → _id`, `cascadeOnDestroy`, and enables Sails **field encryption** (`dataEncryptionKeys`). Models: `Application`, `Applicant`, `ApplicantVerification`, `VerificationAnswer`.
- **Redis** for session + app cache (prefix `hosted_apply_`).
- **Optimizely** for feature flags (`sails.optimizely`), datafile auto-refresh every 5 min.

### Observability
OpenTelemetry replaces the old dd-trace. It is enabled by process flags, **not by app code**: `release.Dockerfile` sets `NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register --require ./otel-log-setup.js"`. `otel-log-setup.js` patches `console.*` to also emit OTLP logs with trace context and registers Node runtime metrics. Running `node app.js` locally does **not** load OTel unless you set those `NODE_OPTIONS` yourself.

### Assets & build
Front-end assets in `assets/` are built by **`sails-hook-shipwright`** (rsbuild under the hood), configured in **`config/shipwright.js`** — this replaced the old Grunt pipeline (Grunt hook is disabled in `.sailsrc`). The config is heavily commented and encodes deliberate decisions: jQuery loads as a global via `inject` and bundled UMD plugins resolve it through `externals: { jquery: 'jQuery' }`; some CSS is injected as raw `<link>`s and copied through untouched (`cssLoader: { url: false }`) rather than bundled. Read those comments before changing asset wiring — several exclusions/orderings are load-bearing.

## Conventions & gotchas
- **Hashes**: user-facing URLs are `slug + trailing hashid` (e.g. `/job/naval-architect-4emx7lc4OnqJtWgkfVE5y`); always decode the last `-`-delimited segment.
- **Sockets are disabled** (`.sailsrc`).
- Unit tests avoid lifting Sails: use `test/helpers/sails-stub.js` (fake `sails` global with sinon stubs) + `test/helpers/mock-express.js` (req/res mocks) + `proxyquire` for module deps. Integration tests use the real lift via `lifecycle.spec.js`.
- Lint is strict (`--max-warnings=0`) and coverage thresholds are enforced — run both before considering a change done.
- Inline ticket-reference comments (`APPSYS-###`, `AS-###`, dates) mark historical changes; follow that style when annotating non-obvious fixes.
