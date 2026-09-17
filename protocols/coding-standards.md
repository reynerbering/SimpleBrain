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

⚠️ **`CoreAPI` has two test projects and they are not interchangeable.** `CoreAPI.Test` is the
legacy NUnit suite against a hand-seeded container; `tests/CoreAPI.Tests.Integration` builds its own
schema from checked-in scripts and is the one to trust and to extend. `dotnet test` with no project
runs both. Which `dotnet` is on PATH matters — see [the CoreAPI repo note](../wiki/repos/CBS-CoreAPI.md).

**Pin the test command per repo before the first pipeline run there.** The Tester stage executes a real suite; without a known runner it guesses, and a guessed green is worse than no test at all. Add a row the first time the pipeline touches a repo — a repo with no row here has not been verified.

This table records only commands **verified by actually running them**.

| Repo | Test command | Build command | Confirmed |
| --- | --- | --- | --- |
| `CoreAPI` (legacy suite) | `dotnet test CoreAPI.Test/CoreAPI.Test.csproj` — **needs the local MSSQL container up**, see notes | `dotnet build CoreAPI.sln` | ✅ 2026-09-18 — **383 / 383**, 1m51s. Build clean (0 errors, 663 warnings) |
| `CoreAPI` (integration suite) | `dotnet test tests/CoreAPI.Tests.Integration/CoreAPI.Tests.Integration.csproj` — **self-contained**, spins its own Testcontainers SQL Server + Valkey. Only needs Docker | `dotnet build CoreAPI.sln` | ✅ 2026-09-18 — **950 passed / 3 skipped / 953**, 2m09s |

⚠️ **`CoreAPI` moved to .NET 10 on 2026-09-10** — commit `ee28457e`, "CBS-4668: Upgrade Core API
to .NET 10". EF Core went 7.0.20 → 10.0.12 and the repo adopted central package management
(`Directory.Packages.props`). Consequences for running anything there:

- **A .NET 10 SDK is required.** With only a 9.x SDK every project fails restore with
  `NETSDK1045: The current .NET SDK does not support targeting .NET 10.0` — the repo does not build
  at all. There is no `global.json` pinning a version.
- **EF Core 10 renamed generated query parameters** — EF9's `__jobId_Value` became `@jobId_Value`.
  Any test asserting on generated SQL **by parameter name** breaks on the upgrade. Assert on the
  emitted predicate instead (`[j].[job_id] =`), which is what such a test is really guarding.
  This bit exactly one test — `PostingQueries_ChildPostingFilter_Tests` — fixed on the CBS-4643
  branch (`81a54c2a`, **not yet merged**). It was the only generated-SQL name assertion in either
  test project, so nothing else is exposed.
- The old 367/367 figure was taken on a **pre-upgrade checkout** (`fcf24ca5` and friends do not
  contain `ee28457e`), which is why it read as .NET 6 despite being dated after the merge. Test
  count is now **383**, so 367 was never a like-for-like baseline. Do not compare the two.
- The upgrade itself is **clean**: 0 build errors, and **exactly one** of the 85 failures is
  net10/EF10 related — the parameter-name assertion above. The other 84 are container drift.
  Verified absent: nullable/ImplicitUsings errors, obsolete-API escalations.
  ⚠️ The earlier count of "84 failed / 299 passed, none net10-related" was one test short;
  re-measured on the rebased branch it is **85 / 298**. Do not reuse the old split.

⚠️ **The seeded container drifts from `develop` and it reads as a code failure.** `CoreAPI.Test`'s
schema is managed outside the repo, so an entity change can land with no migration and the container
silently falls behind. The failures never name the cause: `CoreApiClient` swallows `SqlException`
into `Either.Neither`, so **one missing column produced 84 of 383 failures** across fixtures with
nothing to do with it — `"Job creation failed."` (57×), `Expected: True / But was: False` (19×),
`NullReferenceException` (5×).

**This is now handled in the repo, not here.** `CoreAPI.Test/Scripts/000_schema_drift.sql` records
the deltas and `LegacyDatabaseSchemaFixture` applies them once per run, so a fresh container
self-heals. How to add an entry is `CoreAPI.Test/README.md` — **the repo wins, do not restate it
here.** Landed on the CBS-4643 branch (`55b6aa90`), **not yet merged**; until it is, a fresh
container still needs the delta applied by hand.

What stays mine:

- **Before blaming code for a mass failure here, diff the EF model against the container schema.**
  A full sweep on 2026-09-18 found exactly one delta out of 705 mapped columns — drift is narrow but
  real, and it is the first thing to rule out, not the last.
- **Sibling tables are the tell.** The known delta was `jobs_info_long.site_id` (CBS-4590,
  `6e060d21`); `jobs_info_short` and `jobs_info_medium` already carried `site_id int NULL`. Take a
  column's type and nullability from its siblings and the mapped property, never from a guess.

⚠️ **`CoreAPI` is only green with a local SQL Server on `localhost:1433`.** Without it the same
command returns **192 failed / 175 passed** — every failure an identical
`OneTimeSetUp: SqlException: A network-related or instance-specific error occurred`, not one real
assertion. 192 of the then-367 tests spin a `WebApplicationFactory` against a real DB (Respawn) —
that count predates the .NET 10 upgrade and the suite is now 383; the no-container split has not
been re-measured since.
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
