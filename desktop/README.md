# Water District desktop

The Admin and Staff application uses Avalonia, MVVM, an ASP.NET Core API and EF Core PostgreSQL. The Flutter consumer app remains at the repository root. Both use one shared operational Supabase database.

## Build and run

Install the .NET 10 SDK with Visual Studio support, then open `WaterDistrict.sln`. Set WaterDistrict.Api and WaterDistrict.Desktop as startup projects, or run from the repository root:

```powershell
dotnet restore desktop/WaterDistrict.sln
dotnet build desktop/WaterDistrict.sln
dotnet run --project desktop/src/WaterDistrict.Api
# In a second terminal:
dotnet run --project desktop/src/WaterDistrict.Desktop
```

The API uses loopback port 5181. The desktop signs in with the preconfigured Supabase public URL/key and checks the active Admin/Staff profile through the API. Tokens stay in memory and expiry requires sign-in again. There are no seeded passwords or production authentication bypasses.

## Operational workflows

- Open Service concerns to retrieve consumer submissions or create an office report using active account lookup. Search subject/account number and filter status. New office reports have a stable request identifier so retrying a confirmed/same submission does not create another record.
- Review a concern as Under review, or close it with a response when no repair is needed. Linked tickets control their concern outcome. Original submission details remain intact.
- Admin creates an Open repair ticket from a reviewed concern, then assigns active Staff. A concern can have one ticket.
- Assigned Staff can record In progress, then Resolved, with a required note. Admin can assign/reassign. Each successful change appends history, and resolution updates the consumer-visible concern response.
- PostgreSQL coordinates the ticket, history and concern state. Invalid transitions, inactive assignees, unauthorized users and stale versions are rejected. Refresh before retrying after uncertain connectivity; drafts remain until confirmed success or explicit clearing.

Lists show up to 500 recent matches; account lookup returns up to 200 matches. Narrow search/filter to find older records. Progress reflects recorded staff actions, not automatic field monitoring.

## Shared database setup and migrations

The public REST URL/key cannot substitute for a PostgreSQL connection string. Keep database credentials in API user secrets, the backend `ConnectionStrings__WaterDistrict` environment variable, or an ignored `src/WaterDistrict.Api/appsettings.Local.json` based on the example file. The database CLI reads the environment variable. Use the hostname, user, pooling and SSL settings supplied by Supabase.

```powershell
# After securely setting ConnectionStrings__WaterDistrict locally:
dotnet run --project desktop/tools/WaterDistrict.Database -- --inspect
# Only after catalog review, backup and rehearsal:
dotnet run --project desktop/tools/WaterDistrict.Database -- --migrate
```

The default inspection mode is read-only. The migration preflight refuses incompatible types, existing workflow triggers/history and duplicate tickets. Existing base tables are excluded from EF-generated creation/deletion; Supabase Auth is externally managed. Additive migration SQL adds assignment identity, dispatch marker, history and shared integrity triggers. Existing tickets get one explicitly labelled upgrade snapshot, not invented past events. Automated downgrade is refused to preserve operational history.

No normal startup path creates, resets or migrates the database. For an empty local development database only, `--bootstrap-development` reconstructs the consumer contract and applies the migration; it requires a loopback database named `waterdistrict_dev...` and inserts no operational records. This baseline is not a verified production schema dump.

`/health` reports process liveness. `/health/ready` returns 503 for absent configuration, unavailable PostgreSQL or missing workflow schema. Workflow processing rejects an unapplied EF migration instead of silently bypassing history rules.

Full live Supabase catalog review, profile Staff constraint changes, grants/RLS verification and office-user provisioning are pending authorized database access. See the source repository's `docs/office-account-setup.md` and `docs/database-contract.md`. The API connection is trusted server-side infrastructure; never distribute it to consumer or desktop clients. Preserve the profile permission checks and consumer RLS.

## Verification

```powershell
# Set WATERDISTRICT_TEST_POSTGRES to a loopback PostgreSQL administration connection.
.\desktop\scripts\verify.ps1 -RequirePostgres
```

Tests create/drop uniquely named test databases, apply the actual EF migration, and assert persisted success/failure behavior. Without a test connection, relational tests explicitly skip. A build or unit-only run does not prove database rollback. TRX results go under `desktop/artifacts/test-results`; headless UI previews are under the test output's `artifacts/ui`.

Consumer verification uses Flutter/Dart 3.13.1 or later compatible SDK:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

## Windows x64 release

```powershell
.\desktop\scripts\publish.ps1
```

The new timestamped folder under `desktop/artifacts/release` contains self-contained Desktop, Api and Database executables, setup documentation, a launcher and checksum manifest. Local configuration overrides are excluded. Run `launch.ps1` from that output; it starts the local API and opens the desktop, stopping that API when the desktop exits. Configure backend secrets in the published Api folder afterward. PostgreSQL/Supabase are separate dependencies. For a shared remote API, use HTTPS and configure its host in AllowedHosts; open the Desktop executable directly.

Public desktop settings can be overridden in an ignored desktop `appsettings.Local.json` or variables such as `WATERDISTRICT_Api__BaseUrl`. Plain HTTP is accepted only for loopback development. Database passwords belong solely in backend configuration.

Restore EF tooling from the desktop directory with `dotnet tool restore`. The design-time context reads the backend connection environment variable. Generate SQL with `dotnet tool run dotnet-ef -- migrations script --idempotent --project src/WaterDistrict.Infrastructure --startup-project src/WaterDistrict.Infrastructure` for review; it is never applied automatically.

See `docs/acceptance-verification.md` and `docs/release-and-demonstration.md` in the source repository, or the release's Docs folder, for acceptance results, remaining live checks and the 8?10 minute demonstration. Instructor approval/student IDs remain pending. Billing, payments, notices, online payment, tariff computation and automatic physical-work monitoring are outside the required desktop scope.
