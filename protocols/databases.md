# Database Routing

> **Single source of truth.** Scope: **travels** — the MCP servers are configured at user level and reachable from every repo.
> `CLAUDE.md` imports this file. Do not restate any of it there or in `README.md`.

Three database families are wired up as MCP servers. Each one belongs to exactly one project. **When Neru names a database engine, resolve it to the project below — do not ask which project he means, and do not guess a different one.**

## The routing table

| He says | Engine | Server prefix | Project | Repo |
| --- | --- | --- | --- | --- |
| "mssql", "64recs", "core DB", "SQL Server" | MS SQL Server | `*-64recs-mssql` | **Core** | `CoreAPI` (CBS) |
| "postgres", "default location" | PostgreSQL (Aurora) | `postgres-default-location*` | **Core** | `CoreAPI` (CBS) — *the default-location feature only, see below* |
| "mariadb", "mysql", "recruitsite DB" | MariaDB (RDS) | `mariadb-*` | **RecruitSite 2.0** | `recruitsite-02` (AS) |

- Repo folder names and team ownership come from the repo tables in [`README.md`](../README.md) — the only copy.
- A `CoreAPI` question can mean either engine. **Postgres is the narrow one** — it holds exactly one table. If the question is not about default locations, it is MSSQL.

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

## What Postgres actually covers in CoreAPI

Verified by reading the repo on 2026-09-16 — `CoreAPI/appsettings.json`, `CoreAPI.DataAccess/`, `CoreAPI.Endpoints.V2/`.

**`defaultlocationDB` holds one table: `default_location_settings`.** That is the whole Postgres surface. Everything else in CoreAPI is MSSQL.

- Reached through `DefaultLocationContext` (`CoreAPI.DataAccess/DefaultLocationContext.cs`), registered with `AddNpgsqlContextPool` in `DependencyInjection.cs`. Every other context is `AddSqlServerContextPool`.
- Entity + column mapping: `CoreAPI.DataAccess/Entities/DefaultLocationSettingsEntity.cs`. Queries and commands: `CoreAPI.DataAccess/Features/DefaultLocationFeatures/`. Service: `Services/DefaultLocationService.cs`.
- ⚠️ **Columns are snake_case in the DB, PascalCase in C#** — `entity_type`, `entity_id`, `city`, `region`, `country`, `country_code`, `postal_code`, `created_at/by`, `updated_at/by`. Write MCP SQL against the snake_case names, not the entity property names. Unique index on `(entity_type, entity_id)`.

**The six endpoints that touch it** — `CompanyController.cs` and `DivisionController.cs`:

- `GET|PUT|DELETE /api/v2/company/{companyId}/defaultLocation`
- `GET|PUT|DELETE /api/v2/division/{divisionId}/defaultLocation`

One indirect reader: `JobService` takes `IDefaultLocationService`, so job creation resolves a default location and can hit Postgres without any `/defaultLocation` route being called.

## The other CoreAPI connection strings

`CoreAPI/appsettings.json` → `ConnectionStrings`. Relevant because **not all of them are reachable over MCP**.

| Key | Target | Context | MCP server? |
| --- | --- | --- | --- |
| `Default`, `DefaultReadOnly` | MSSQL `64recs67o` | `DataContext`, `DataContextReadOnly` | ✅ the `*-64recs-mssql` servers |
| `Secure`, `SecureReadOnly` | MSSQL `64recs67o` (different login) | `SecureContext`, `SecureContextReadOnly` | ✅ same DB, so same server |
| `OcApi` | MSSQL **`OCApi`** — same host, **different database** | `OcApiContext` | ⚠️ reachable, but only three-part names — see below |
| `DefaultLocation` | Postgres `defaultlocationDB` | `DefaultLocationContext` | ✅ the `postgres-default-location*` servers |
| `SourcingAppMongoDB`, `AnalyticsMongoDB` | MongoDB | — | ❌ no MCP server configured |

### Reaching the other databases on the MSSQL host

The login sees **18 databases** on the instance, not just `64recs67o` (checked against prod on 2026-09-16). `MSSQL_DATABASE=64recs67o` only sets the *default*.

- `mssql_execute_query` **can** cross databases with three-part names — `SELECT ... FROM OCApi.sys.tables` works. Verified.
- The introspection tools (`mssql_list_tables`, `mssql_get_table_ddl`, `mssql_search_columns`, …) resolve against the connected database. For anything outside `64recs67o`, query `<db>.sys.*` / `<db>.INFORMATION_SCHEMA.*` directly instead.
- Other databases on that instance: `Analytics`, `api`, `autoconfirm`, `Boards`, `bouncemail`, `company`, `DBMaint`, `ftp`, `insight`, `job_matching`, `jobdistribution`, `jobinput`, `jobprocess`, `OCApi`, `recruitsite`, `SalaryData`, `zipcodes`.

⚠️ **`recruitsite` on the MSSQL host is not RecruitSite 2.0's database.** RecruitSite 2.0 runs on MariaDB (`*_recruitsite` RDS). The MSSQL `recruitsite` DB is a separate, older thing — never resolve "recruitsite DB" to it without saying which one you mean.
