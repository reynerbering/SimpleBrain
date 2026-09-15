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
| _(none pinned yet)_ | | | |

**Before any pipeline run, read the test-readiness section in [`README.md`](../README.md)** — the only copy. 11 of the 24 owned repos have no tests at all, and several declare commands pointing at missing files.

## Per-repo overrides

If a repo needs something other than the above, put it in **that repo's `CLAUDE.md`**, not here. It travels with the code and works for teammates too.

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
