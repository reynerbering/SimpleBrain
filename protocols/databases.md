# Database Routing

> **Single source of truth.** Scope: **travels** — the MCP servers are configured at user level and reachable from every repo.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

Three database families are wired up as MCP servers. Each one belongs to exactly one project. **When Neru names a database engine, resolve it to the project below — do not ask which project he means, and do not guess a different one.**

## The routing table

| He says | Engine | Server prefix | Project | Repo |
| --- | --- | --- | --- | --- |
| "mssql", "64recs", "core DB", "SQL Server" | MS SQL Server | `*-64recs-mssql` | **Core** | `CoreAPI` (CBS) |
| "postgres", "default location" | PostgreSQL (Aurora) | `postgres-default-location*` | **Core** | `CoreAPI` (CBS) |
| "mariadb", "mysql", "recruitsite DB" | MariaDB (RDS) | `mariadb-*` | **RecruitSite 2.0** | `recruitsite-02` (AS) |

- Repo folder names and team ownership come from the repo tables in [`README.md`](../README.md) — the only copy.
- Reading code *and* its data is the normal case: a `CoreAPI` question can mean either MSSQL or Postgres. Pick by what the question is about, or ask.

## Always ask which environment

**Never pick an environment yourself.** Every family has QA / UAT / PROD wired separately, and the names look alike. Ask before the first query of a session, then reuse the answer.

| Family | QA | UAT | PROD |
| --- | --- | --- | --- |
| MSSQL | `qa-64recs-mssql` | `uat-64recs-mssql` | `prod-64recs-mssql` |
| Postgres | `postgres-default-location` | `postgres-default-location-uat` | `postgres-default-location-prod` |
| MariaDB | `mariadb-qa` | `mariadb-uat` | `mariadb-prod` |

⚠️ The QA Postgres server is named `postgres-default-location` with **no suffix** — the bare name is QA, not prod. Easy to misread as "the default one".

## Write safety

Guardrails are uneven. Do not assume a server will refuse a bad query.

- **MariaDB** — prod and UAT are `MCP_READ_ONLY=true`. **QA is writable.**
- **Postgres** — QA and prod run `--access-mode=restricted`. **UAT runs `--access-mode=unrestricted`.**
- **MSSQL** — no read-only mode on any of the three. `mssql_execute_write_query` is exposed on **prod**. Nothing stops a write there but this rule: never call a write tool against any MSSQL server without Neru asking for that write in the same breath.

## What's actually behind each server

Read from the MCP config and env files on 2026-09-16. Not guessed.

**MSSQL — database `64recs67o` on all three**

- QA `jtawssqldev05.jobtarget.com` · UAT `jtawssqlstag.jobtarget.com` · PROD `jtawssql-lstnr.jobtarget.com`
- Port 1433, `MSSQL_ENCRYPT=false`, `TRUST_SERVER_CERTIFICATE=true`.

**Postgres — database `defaultlocationDB` on all three**, Aurora clusters in `us-east-1`

- Server `crystaldba/postgres-mcp` in Docker, URI from `PG_DATABASE_URI_{QA,UAT,PROD}`.

**MariaDB — RDS in `us-east-1`, one DB per environment**

- QA `qa_recruitesite` · UAT `uat-recruitsite` · PROD `prod_recruitsite` (note the QA/UAT typo-ish spellings — they are the real names).
- Server lives at `C:\Users\r.bering\mcp-servers\mariadb-mcp`, env picked by `MARIADB_ENV_FILE`. TLS required; CA bundle is `rds-global-bundle.pem` in that folder.

## Open question

- **Postgres → `CoreAPI` is Neru's mapping, stated 2026-09-16, not verified in code.** The DB is `defaultlocationDB` and no repo named `default-location` exists in the inventory. If a connection string in `CoreAPI` confirms it, delete this bullet. If it turns out to be a different service's DB, fix the table.
