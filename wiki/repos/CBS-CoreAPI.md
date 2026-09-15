---
type: repo-memory
team: CBS
repos:
  - CoreAPI
source: "C:\JT Repositories\CoreAPI\CLAUDE.md"
captured: 2026-09-15
sha256_short: 3dffb48e12f9
updated: 2026-09-15
---

# CoreAPI — repo memory

> **Snapshot, not the source.** The live file is `C:\JT Repositories\CoreAPI\CLAUDE.md` — that is what Claude Code actually loads in the repo. This is a read-only copy captured 2026-09-15 (162 lines, sha256 `3dffb48e12f9`) so the vault can answer questions about repo conventions without opening the repo.
> Edit the repo's file, then re-import. Never edit this copy and expect it to take effect.
>
> Below this line is the repo's own content, verbatim. Per [coding-standards](../../protocols/coding-standards.md), a repo's conventions win inside that repo — so vault [wiki voice](../../protocols/wiki-voice.md) does **not** apply to it and it has not been rewritten.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Restore packages
dotnet restore

# Build solution
dotnet build

# Run the API (Swagger at https://localhost:5001/swagger/index.html)
dotnet run --project CoreAPI

# Run all tests
dotnet test

# Run a single test class or method
dotnet test --filter "FullyQualifiedName~YourTestClassName"
dotnet test --filter "FullyQualifiedName~YourTestClassName.YourMethodName"
```

### Integration Test Setup

Integration tests require a local SQL Server container. Run once before testing:

```bash
docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=&Unit_Testing&" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2019-latest
```

Then in `CoreAPI.TestFramework/CoreApiTestFramework.cs`, replace the `jtmssql` hostname with `localhost`. Disconnect from the JobTarget VPN before running integration tests to avoid touching shared databases.

## Architecture

### Solution Projects

| Project | Purpose |
|---------|---------|
| `CoreAPI` | ASP.NET Core host: `Program.cs`, middleware, DI registration |
| `CoreAPI.Public` | Domain models, DTOs, enums, interfaces — the shared contract |
| `CoreAPI.Endpoints.V1` | Legacy V1 controllers (no new features; deprecated) |
| `CoreAPI.Endpoints.V2` | Current V2 controllers (all new work goes here) |
| `CoreAPI.Endpoints.Experiments` | Experimental endpoints for in-flight features |
| `CoreAPI.DataAccess` | EF Core `DataContext` / `SecureContext` / `OcApiContext` + repositories |
| `CoreAPI.DataAccess.DynamoDb` | DynamoDB-specific repositories |
| `CoreAPI.Common` | Shared utilities, authorization helpers, cross-cutting services |
| `CoreAPI.FluentValidation` | Centralized FluentValidation rule sets |
| `CoreAPI.Client` | NuGet client package for consuming V2 endpoints |
| `CoreAPI.Test` | xUnit/NUnit integration and API test suite |
| `CoreAPI.TestFramework` | `WebApplicationFactory`-based test infrastructure |

### Domain Layout

All business domains live under `CoreAPI.Public/Domains/<Domain>/`. A typical domain contains:

- Root models (`Job.cs`, `JobData.cs`, etc.)
- `Enum/` — domain-specific enumerations
- `RequestErrorCodes/` — typed error codes per operation
- `ValidationErrorCodes/` — typed validation failure codes
- `RequestParameters/` — query/filter parameter models

Controllers in `CoreAPI.Endpoints.V2/<Domain>/`, services in `CoreAPI.Common` or domain-specific service folders, validators in `CoreAPI.FluentValidation/<Domain>/`, and EF entities/repos in `CoreAPI.DataAccess/`.

### Key Patterns

**Thin controllers with functional error handling.** Controllers extend `CoreApiControllerBase` which provides `MakeErrorResponse()`. Business logic lives in services. Results flow through EasyMonads types — `Maybe<T>` for optional values and `Either<L, R>` for typed success/failure — and are pattern-matched at the controller boundary:

```csharp
return await _jobService.GetJobAsync(jobId, cancellationToken)
    .MatchAsync(
        () => MakeErrorResponse(HttpStatusCode.NotFound, GetJobErrorCode.NotFound),
        Ok);
```

Never throw exceptions for domain errors; use `Either`/`Maybe` instead.

**Static query/command classes.** Services delegate EF Core operations to static classes co-located in `CoreAPI.DataAccess`:

```csharp
// Read (uses DataContextReadOnly)
var result = await JobQueries.GetJobAsync(_dataContextReadOnly, jobId);

// Write (uses DataContext) + SNS publish
var result = await JobCreateCommands.CreateJobAsync(_dataContext, jobData);
await result.DoRightAsync(async job =>
    await _jobSnsService.SendMessageAsync(new JobNotification(JobNotificationAction.Create, job), ModelAction.Create));
```

**Read/write separation.** Inject `DataContext` for writes and `DataContextReadOnly` for all queries. Four distinct DbContexts exist: `DataContext`, `DataContextReadOnly`, `SecureContext`, `OcApiContext`.

**DbContext pooling (CBS-4124).** All six contexts are registered with `AddDbContextPool` in `CoreAPI.DataAccess/DependencyInjection.cs`, not `AddDbContext`. Pooled instances are reset and reused across requests, which imposes hard rules — breaking them causes silent cross-request state bleed (worst on the PII `SecureContext`):

- **All configuration lives in the `AddDbContextPool((provider, options) => …)` lambda** — connection string, `CommandTimeout`, `EnableRetryOnFailure`, `NoTracking` (read-only contexts), and `AddQueryHints()` (the `DataContext`/`DataContextReadOnly` interceptor). `OnConfiguring` is **never called** for pooled contexts; do not add it back.
- **Each context has exactly one public constructor** taking `DbContextOptions<T>`. The write base classes (`DataContext`, `SecureContext`) also expose a **`protected` non-generic `DbContextOptions` ctor** so their read-only subclasses bind to it. Do not add a second public ctor (parameterless or `IOptions`) — pooling registration will throw.
- **No mutable instance fields, no event subscriptions** (`ChangeTracker.Tracked/StateChanged`, `SavingChanges`, …), and **no scoped services injected into the constructor** — EF resolves ctor dependencies once from the first scope and reuses them; only singletons (e.g. `IOptions`) are safe. Only the `ChangeTracker` is reset between leases.
- The EF context pool uses EF Core's default size (1024). This is a separate layer from the ADO.NET connection pool — actual DB connection concurrency is bounded by the `Max Pool Size` in the connection string, independently of the context-pool size, so the two need not be coupled.
- To construct one of these contexts directly (e.g. a one-off in a test), build options yourself: `new SecureContext(new DbContextOptionsBuilder<SecureContext>().UseSqlServer(conn).Options)`.
- If you ever need per-request/per-tenant connection routing or scoped-service injection, switch that registration to `AddPooledDbContextFactory` rather than re-adding state to the context.

**FluentValidation auto-discovery.** Validators in `CoreAPI.FluentValidation` are discovered automatically. Error messages are enum descriptions:

```csharp
RuleFor(x => x.Name)
    .NotEmpty()
    .WithMessage(CompanyDataValidationErrorCode.MissingName.GetDescriptionFromEnumValue());
```

Data annotations validation is disabled; FluentValidation is the sole validation mechanism.

**SNS events via abstract base.** `AbstractSnsService<T>` in `CoreAPI.Common` handles serialization, S3 offload (payloads >200 KB), and message attribute stamping (`Action`, `Origin`). Each domain gets a concrete `<Domain>SnsService` registered in DI. Events are fire-and-forget after successful writes.

**API key auth.** Every request requires `X-API-KEY`. The custom `ApiKeyAuthorizationHandler` validates the header, builds role claims from `AuthorizationSettings`, and rejects with a typed JSON error on failure. Roles use the `"Domain/Action"` format (e.g., `"User/Create"`).

**DI via extension methods.** Each layer exposes an `AddXxx()` extension method (`AddEndpointServicesV2()`, `AddDataAccess()`, etc.) called from `Program.cs`. New services are registered in the layer's own `DependencyInjection.cs`, not in `Program.cs` directly.

**Exception middleware.** `ExceptionHandlerMiddleware` maps known exceptions to HTTP status codes (`EnumInvalidValueException` → 400, SQL timeout → 500 with `DatabaseTimeout` error code, `TaskCanceledException` → 408) and returns a standardized `ErrorResponseModel`.

### Adding a New Domain

1. Define models and DTOs in `CoreAPI.Public/Domains/<NewDomain>/`
2. Add validators in `CoreAPI.FluentValidation/<NewDomain>/`
3. Add EF entities and static `<Domain>Queries` / `<Domain>Commands` classes in `CoreAPI.DataAccess/`
4. Add a concrete `<Domain>SnsService` extending `AbstractSnsService<T>`, configure its topic/bucket in `appsettings.json` under `SnsSettings`
5. Implement services and register them in the layer's `DependencyInjection.cs`
6. Add V2 controllers in `CoreAPI.Endpoints.V2/<NewDomain>/`
7. Add client handler in `CoreAPI.Client/`

### Testing

Tests use NUnit with `WebApplicationFactory<Program>` and `Respawn` for database reset. The standard fixture setup:

```csharp
[OneTimeSetUp]
public async Task OneTimeSetUp()
{
    _testFramework = new CoreApiTestFramework();
    _factory = _testFramework.SetupWebApplicationFactor();
    _client = CoreApiTestFramework.SetupCoreApiClient(_factory.CreateClient());
    await _testFramework.InitializeDatabaseConnectionsAsync();
}

[TearDown]
public async Task TearDown() => await _testFramework.ResetDatabases();
```

`CoreApiTestFramework` stubs out external dependencies (Redis, DynamoDB, legacy encryption, hosted-apply URL generation) automatically.

### Branching

- Base all work off `develop`; PRs target `develop`
- Branch format: `CBS-<ticket>-short-description`
- `main` receives release branches after final QA

## Environments

| Environment | URL |
|-------------|-----|
| Production | https://core-api.jobtarget.com/ |
| UAT | https://uat-core-api.jobtarget.com/swagger/index.html |
| QA | https://qa-core-api.jobtarget.com/swagger/index.html |
