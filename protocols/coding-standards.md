# Coding Standards

> **Single source of truth.** Scope: **travels** — applies in every repo.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

**Stacks in play:** .NET (C#) and Node/TypeScript. Anything outside these two is unconfirmed — ask before assuming a language, framework, test runner, or lint setup.

**Resolution order**, highest wins:

1. A row in the **pinned commands** table below — verified by actually running it.
2. The repo's **own `CLAUDE.md`**.
3. The **stack defaults** below — a first guess to confirm, never a command to run blind.

## Stack defaults

Conventional starting points, **not verified against any specific repo**.

### C# / .NET

- **Detect:** `.sln` or `.csproj`
- **Test:** `dotnet test` — solution-scoped by default; a repo may need `--filter` or a named `.sln`
- **Build:** `dotnet build`
- **Framework:** match whatever the repo already uses — xUnit, NUnit, or MSTest. Never introduce a second one.

### Node / TypeScript

- **Detect:** `package.json`
- **Test:** the `test` script in `package.json`. Read it before running it — several repos declare a `test` script that points at a file that does not exist.
- **Build:** the `build` script in `package.json`, if there is one.
- **Package manager:** from the lockfile. Never switch. pnpm and yarn are not interchangeable with npm here.

## Per-repo pinned commands

**Pin the test command per repo before the first pipeline run there.** The Tester stage executes a real suite; without a known runner it guesses, and a guessed green is worse than no test at all. Add a row the first time the pipeline touches a repo — a repo with no row here has not been verified.

This table records only commands **verified by actually running them**.

| Repo | Test command | Build command | Confirmed |
| --- | --- | --- | --- |
| `CoreAPI` | `dotnet test CoreAPI.Test/CoreAPI.Test.csproj` — **needs the local MSSQL container up AND schema-current**, see notes | `dotnet build CoreAPI.Test/CoreAPI.Test.csproj` | ⚠️ 2026-09-18 — **84 failed / 299 passed / 383 total**, 1m44s. Build clean. Red for environment drift, not code — see below |

⚠️ **`CoreAPI` moved to .NET 10 on 2026-09-10** — commit `ee28457e`, "CBS-4668: Upgrade Core API
to .NET 10". EF Core went 7.0.20 → 10.0.12 and the repo adopted central package management
(`Directory.Packages.props`). Consequences for running anything there:

- **A .NET 10 SDK is required.** With only a 9.x SDK every project fails restore with
  `NETSDK1045: The current .NET SDK does not support targeting .NET 10.0` — the repo does not build
  at all. There is no `global.json` pinning a version.
- **EF Core 10 renamed generated query parameters** — `@__jobId_Value_0` became `@jobId_Value`. Any
  test asserting on generated SQL by parameter name breaks on the upgrade. Assert on the emitted
  predicate instead.
- The old 367/367 figure was taken on a **pre-upgrade checkout** (`fcf24ca5` and friends do not
  contain `ee28457e`), which is why it read as .NET 6 despite being dated after the merge. Test
  count is now **383**, so 367 was never a like-for-like baseline. Do not compare the two.
- The upgrade itself is **clean**: 0 build errors, and none of the 84 failures are net10/EF10
  related. Verified absent: EF parameter-name breaks, nullable/ImplicitUsings errors, obsolete-API
  escalations.

⚠️ **The seeded container drifts from `develop` and it looks like a code failure.** As of
2026-09-18 `coreapi-test-sql` is missing **`jobs_info_long.site_id`**, mapped by
`JobInfoLongEntity.cs` since commit `6e060d21` (CBS-4590, 2026-09-01). Schema is managed outside
the repo, so an entity change can land with no migration and the container silently falls behind.

- **One missing column caused 84 of 383 failures** — every fixture that seeds a job via
  `POST /api/v2/division/{id}/user/{id}/job`. It surfaces as `"Job creation failed."` (57×),
  `Expected: True / But was: False` (22×), and `NullReferenceException` (5×), never as the real
  error: the client swallows exceptions into `Either.Neither`, hiding
  `SqlException: Invalid column name 'site_id'`.
- **Sibling tables are the tell** — `jobs_info_short` and `jobs_info_medium` both have
  `site_id int NULL`; only `jobs_info_long` lacks it.
- Fix is `ALTER TABLE [64recs67o].dbo.jobs_info_long ADD site_id INT NULL;` — type and nullability
  confirmed against both siblings and the `int? SiteId` property, not guessed.
- **Before blaming code for a mass failure here, diff the EF model against the container schema.**
  A full sweep on 2026-09-18 found exactly one delta out of 705 mapped columns, so drift is narrow
  but real.

⚠️ **`CoreAPI` is only green with a local SQL Server on `localhost:1433`.** Without it the same
command returns **192 failed / 175 passed** — every failure an identical
`OneTimeSetUp: SqlException: A network-related or instance-specific error occurred`, not one real
assertion. 192 of the 367 tests spin a `WebApplicationFactory` against a real DB (Respawn).
Setup is the repo's own — `CoreAPI.Test/README.md` and the repo `CLAUDE.md`; **the repo wins, do not
restate it here**. Two gotchas worth knowing before blaming the code:

- The container **stops every time Docker Desktop restarts**, so a red run usually means "not running",
  not "broken".
- Reuse the existing seeded container (`docker start coreapi-test-sql`) rather than `docker run`ing a
  fresh one — there is **no volume mount**, so the seeded `64recs67o` and `OCApi` databases live in
  that container's layer. A new container starts empty and fails differently.

**Before any pipeline run, read the test-readiness section in [`README.md`](../README.md)** — the only copy. 11 of the 24 owned repos have no tests at all, and several declare commands pointing at missing files.

## Per-repo overrides

If a repo needs something other than the above, put it in **that repo's `CLAUDE.md`**, not here. It travels with the code and works for teammates too.

Where that file's content actually lives — and which of it belongs in the repo versus the vault — is [the repo memory protocol](repo-memory.md).

```markdown
## Commands
- Test: <exact command>
- Build: <exact command>
- Lint: <exact command>
```

## General

- When a coding convention gets decided, write it **here** rather than rediscovering it each session.
- **`.pipeline/` is gitignored** in every repo that uses the pipeline. It is scratch handoff state, not source.
- When a vault rule and a repo's own conventions conflict inside that repo, **the repo wins**. Say so rather than silently applying a vault rule out of context.
