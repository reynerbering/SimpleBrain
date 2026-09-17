---
type: repo-memory
team: CBS
repos:
  - CoreAPI
layer: personal
consumed_by: "C:\JT Repositories\CoreAPI\CLAUDE.local.md"
updated: 2026-09-18
---

# CoreAPI — my personal layer

**This note is not the whole picture for CoreAPI.** The repo's own `CLAUDE.md` is
tracked in git and co-authored with Shervin Ivari — that file owns the shared,
team-facing conventions (commands, solution layout, integration-test setup) and
is loaded straight from the repo. Do not copy any of it here.

This note holds **only my own additions on top of it**, imported via
`CoreAPI/CLAUDE.local.md`.

## My additions

- **Databases** — CoreAPI is MSSQL (`64recs67o`) everywhere *except* the default-location feature, which is Postgres (`defaultlocationDB`, one table). Which MCP server, which environment, and the `OCApi` cross-database gotcha are in [the database routing protocol](../../protocols/databases.md) — the only copy.

- **.NET 10 SDK lives in my user profile, not on PATH.** CoreAPI needs it since CBS-4668 (see
  [coding standards](../../protocols/coding-standards.md) — the only copy of what the upgrade
  changed). The system install at `C:\Program Files\dotnet` is still 9.0.103 / 9.0.317 and cannot
  build the repo. Mine is `10.0.401` at `~/.dotnet`, installed 2026-09-18 via `dotnet-install.ps1
  -Channel 10.0 -InstallDir "$env:USERPROFILE\.dotnet" -NoPath`. Deliberately off PATH so it does
  not shadow the system SDK for other repos — so every command needs:

  ```bash
  export PATH="$HOME/.dotnet:$PATH" DOTNET_ROOT="$HOME/.dotnet"
  ```

  Symptom when it is missing: `NETSDK1045` on every project, which reads like a repo problem and is not.

<!-- Add personal-only items here: sandbox URLs, local DB creds pattern,
     preferred test filters, habits that are mine and not the team's.
     Anything that belongs to the team goes in the repo's tracked CLAUDE.md
     via a normal PR instead. -->
