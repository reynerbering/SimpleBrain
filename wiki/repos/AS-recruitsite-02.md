---
type: repo-memory
team: AS
repos:
  - recruitsite-02
source: "C:\JT Repositories\recruitsite-02\CLAUDE.md"
captured: 2026-09-15
sha256_short: fd6d16f32060
updated: 2026-09-15
---

# recruitsite-02 — repo memory

> **Snapshot, not the source.** The live file is `C:\JT Repositories\recruitsite-02\CLAUDE.md` — that is what Claude Code actually loads in the repo. This is a read-only copy captured 2026-09-15 (96 lines, sha256 `fd6d16f32060`) so the vault can answer questions about repo conventions without opening the repo.
> Edit the repo's file, then re-import. Never edit this copy and expect it to take effect.
>
> Below this line is the repo's own content, verbatim. Per [coding-standards](../../protocols/coding-standards.md), a repo's conventions win inside that repo — so vault [wiki voice](../../protocols/wiki-voice.md) does **not** apply to it and it has not been rewritten.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**RecruitSite 2.0** — a Laravel 9 (PHP 8.1) app that renders JobTarget customer "microsites": branded, per-company career pages assembled dynamically from database-driven sections and components. It also serves as the **Click2Apply landing/router**: an inbound `/job/{hash}` link is resolved via the Posting Reference API to the correct microsite job-detail page (falling back to HostedApply when lookups fail).

The Laravel application lives entirely in **`site/`**, not the repo root. The repo root holds the Docker/ECS build and observability tooling.

## Layout

- `site/` — the Laravel app (`composer.json`, `artisan`, `app/`, `config/`, `routes/`, `resources/`).
- `Dockerfile`, `docker-compose.yml` — build and local OTel simulation (repo root).
- `ci-build/` — runtime config baked into the image: `entrypoint.sh`, `nginx-default.conf`, `php.ini`, `www.conf` (php-fpm), `emit-target-info.sh`, `otel-collector-config-local.yaml`.
- `LOCAL-OTEL-TEST.md` — how to verify the OTel pipeline locally.

## Commands

All PHP/artisan/composer commands run from **`site/`**; npm commands also run from `site/`.

```bash
# Dependencies
cd site && composer install
cd site && npm ci

# Frontend assets (Vite + Tailwind + Alpine)
cd site && npm run dev       # vite dev server
cd site && npm run build     # production build

# Tests (PHPUnit)
cd site && ./vendor/bin/phpunit
cd site && php artisan test
cd site && php artisan test --filter=ExampleTest    # single test/class

# Lint / format (Laravel Pint)
cd site && ./vendor/bin/pint            # fix
cd site && ./vendor/bin/pint --test     # check only

# Valkey cache management (custom artisan commands)
cd site && php artisan valkey:clear {microsite|jobs|sections|all}
cd site && php artisan valkey:stats
```

### Local OTel pipeline test (from repo root)

```bash
docker compose up --build -d       # app + ADOT collector, ECS-like shared netns
curl.exe -i http://localhost:8080/health
docker compose logs -f otel-collector   # look for span batches
docker compose down -v
```

See `LOCAL-OTEL-TEST.md` for interpreting output. Note: the compose app uses SQLite in-memory, so many routes 500 — that's expected; OTel fires regardless.

## Architecture

### Request flow — page assembly
The core rendering path is `MicrositePageController` (`single()` for the company home, `job()` for a job-detail page). Pages are **composed at request time, not stored as documents**:

`Microsite` → `pages` → `sections` (ordered, `enabled`) → `components` (ordered, `enabled`) → per-component `settings`.

`getSections()` eager-loads that whole tree in one query, then post-processes each component by `type` (`job-list`, `featured-list`, `job-detail`, `apply-widget`, `editor-content`, `search-form`). Section `settings` of type `style`/`contain` carry Tailwind class tokens that become the section's CSS classes. Blade views mirror the component types: `resources/views/components/<type>.blade.php`, wrapped by the `PageStack` Livewire component (`resources/views/livewire/page-stack.blade.php`).

### Click2Apply routing
`RoutingController::index()` handles `/job/{hash}`: calls `POSTING_REFERENCE_API_URL/lookup/{hash}`, walks `JobPosting → PostingSettings → JobList → Microsite` to build the destination `urlname/job/{jobid}` path, preserving original query params (hidden from the URL). Every failure branch redirects to `HOSTEDAPPLY_URL` and caches the result with a shorter TTL.

### Caching — Valkey (Redis-compatible), not Laravel's default
This app uses a **custom `valkey` cache store**, registered by `ValkeyServiceProvider` and configured in `config/valkey.php` + the `valkey` connection in `config/database.php` (`redis.valkey`). Always access it explicitly:

```php
Cache::store('valkey')->get($key);
Cache::store('valkey')->put($key, $value, $ttlSeconds);
```

Cache keys follow dotted namespaces the `valkey:clear` command matches on: `microsite.{slug}.home`, `sections.{siteId}.{page}.{jobid}.{postingId}`, `jobdetail.{jobid}`, `applywidget.{jobid}.{postingId}`, `jobstatus.{jobid}`, `location.{jobid}`, `hashlookup.{hash}`. **`company-top` sections are intentionally NOT cached** so job-list pagination stays correct — preserve this when editing `getSections()`.

### Models / DB conventions
Eloquent models (`Microsite`, `JobPosting`, `PostingSettings`, `JobList`, `MicrositePages`, `MicrositeSections`, `MicrositeComponents`, and their `*Settings`, `MicrositeBranding`, `MicrositeDivisions`) are thin: relations + query scopes, empty `$fillable` (read-heavy app). Prefer scopes (`->posting($jobid)`, `->slug($slug)`, `->joblist($id)`, `->featured()`) over raw wheres. Default DB connection is **MySQL** (`DB_CONNECTION=mysql`); RDS enforces `require_secure_transport=ON`, so `config/database.php` auto-resolves the RDS CA bundle (env `MYSQL_ATTR_SSL_CA` → `/etc/ssl/certs/rds-global-bundle.pem` → `certs/rds-global-bundle.pem`).

### External services (via env)
- `CORE_API_URL` — JobTarget Core API (job status, location); called with `verify => false`.
- `POSTING_REFERENCE_API_URL` — hash → job/posting lookup.
- `HOSTEDAPPLY_URL` — Click2Apply fallback destination.
- S3 (`AWS_BUCKET`) — microsite logos served via short-lived signed URLs (`Storage::disk('s3')->temporaryUrl(...)`), with a graceful fallback to the raw URL when S3 is unavailable (local dev).

### Observability (OpenTelemetry)
Runs on the ECS deployment target as PHP zero-code auto-instrumentation (`open-telemetry/*` composer packages + `php81-pecl-opentelemetry`/`grpc` extensions), exporting OTLP/gRPC to an ADOT sidecar on `localhost:4317`. Two subtleties that have caused production incidents (see git history):
- The composer **lockfile must stay in sync** with `composer.json` or the OTel SDK silently fails to load.
- php-fpm strips env by default — the `env[OTEL_*]` block in `ci-build/www.conf` is what forwards `OTEL_*` vars into workers.
- PHP auto-instrumentation emits traces/logs but **no metrics**, so `emit-target-info.sh` POSTs a `service.up` gauge heartbeat so the collector synthesizes `target_info` for Grafana service discovery.

## Build / deploy notes
- The image is a **two-stage Alpine 3.19 build**: the builder stage runs `entrypoint production` (composer install, `php artisan migrate`, `npm ci`, `npm run build`); the runtime stage deliberately **omits nodejs/npm and the C toolchain** to keep `libuv` (CVE-2024-24806) out of the deployed image — there's a build-time assertion that fails if `libuv` reappears. Do not add runtime packages that pull it back in.
- `ci-build/entrypoint.sh` distinguishes `run_development` vs `run_production` by its first arg; paths reference `/workspace/statamic/site` (historical naming — this is a Laravel app, not Statamic).
- Serves via nginx + php-fpm (port 80). CI/CD is GitLab (`jobtarget/marketing/recruitsite-02`); default branch is `develop`.
