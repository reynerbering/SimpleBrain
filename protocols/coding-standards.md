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
| `CoreAPI` | `dotnet test CoreAPI.Test/CoreAPI.Test.csproj` — **needs the local MSSQL container up**, see note | `dotnet build CoreAPI.Test/CoreAPI.Test.csproj` | ⚠️ 2026-09-17 — 367/367 green, 5m40s, **on .NET 6 — superseded by the upgrade below, re-run pending** |

⚠️ **`CoreAPI` moved to .NET 10 on 2026-09-17** — commit `ee28457e`, "CBS-4668: Upgrade Core API
to .NET 10". EF Core went 7.0.20 → 10.0.12 and the repo adopted central package management
(`Directory.Packages.props`). Consequences for running anything there:

- **A .NET 10 SDK is required.** With only a 9.x SDK every project fails restore with
  `NETSDK1045: The current .NET SDK does not support targeting .NET 10.0` — the repo does not build
  at all. There is no `global.json` pinning a version.
- **EF Core 10 renamed generated query parameters** — `@__jobId_Value_0` became `@jobId_Value`. Any
  test asserting on generated SQL by parameter name breaks on the upgrade. Assert on the emitted
  predicate instead.
- The 367/367 figure above predates all of this and has not been re-established.

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
