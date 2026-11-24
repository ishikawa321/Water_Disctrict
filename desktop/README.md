# Water District desktop

Open `WaterDistrict.sln` in Visual Studio with .NET 10 support. The Flutter project remains at the repository root. The desktop is an Avalonia application; the companion ASP.NET Core API will enforce permissions and use EF Core PostgreSQL for workflow persistence.

## Build and run

From the repository root:

```powershell
dotnet restore desktop/WaterDistrict.sln
dotnet build desktop/WaterDistrict.sln
dotnet test desktop/WaterDistrict.sln
dotnet run --project desktop/src/WaterDistrict.Api
# In another terminal:
dotnet run --project desktop/src/WaterDistrict.Desktop
```

The API listens on `http://127.0.0.1:5181` in development. `/health` reports process liveness. `/health/ready` returns HTTP 503 when PostgreSQL is unconfigured/unavailable; a successful build is not a database verification.

## Backend database configuration

Keep the database password in backend user secrets, environment configuration, or an ignored `appsettings.Local.json` beside API configuration. Never add it to the desktop app or repository. Use the SSL settings from your Supabase connection information. The public REST URL/key cannot replace a PostgreSQL connection string.

```powershell
# Set ConnectionStrings__WaterDistrict in this terminal from a secure local source.
dotnet run --project desktop/tools/WaterDistrict.Database
```

The inspection tool opens a read-only PostgreSQL transaction and prints schema metadata, not operational rows. Alternatively execute `database/inspect.sql` in an authorized SQL session. Review output locally before sharing.

The provisional EF mapping excludes existing profiles from migrations. No startup code resets, creates or migrates the shared database. Catalog inspection and a disposable development database are prerequisites to schema changes. See `../docs/database-contract.md`.

## Sign in as Admin or Staff

The public Supabase project URL and publishable key are preconfigured. Start the API and desktop as shown above, then use an existing verified office account with an active `profiles` row and role `admin` or `staff`. There is no demo password or authentication bypass. An API PostgreSQL connection is not needed for these profile checks: the API queries Supabase with the verified user's access token and RLS. EF Core and the PostgreSQL connection will handle the later business workflows.

Admin sees the active staff directory; Staff sees their own office workspace. Both can refresh access and sign out. Concern/ticket processing is scheduled for Sessions 5?8. Consumer accounts do not have desktop access.

See [office account and database setup](../docs/office-account-setup.md) and the [actual verification record](../docs/session-1-4-verification.md). Live schema and Staff provisioning checks remain pending PostgreSQL administration access.

## Configuration and Visual Studio

Desktop public settings are copied beside the application from `src/WaterDistrict.Desktop/appsettings.json`. Override them in an ignored desktop `appsettings.Local.json` or environment variables such as `WATERDISTRICT_Api__BaseUrl`. Only HTTPS API addresses are accepted except loopback development. Database credentials belong only in API configuration.

For Visual Studio, open `WaterDistrict.sln` and configure multiple startup projects: start `WaterDistrict.Api` and `WaterDistrict.Desktop`. The API launch profile uses port 5181, matching the desktop configuration. Alternatively use the two terminal commands above.

## EF Core tooling

```powershell
Set-Location desktop
dotnet tool restore
dotnet tool run dotnet-ef -- --version
```

The design-time context reads `ConnectionStrings__WaterDistrict`. Generate and review migrations only after inspecting and baselining the existing database. `profiles` is excluded from migrations; Supabase Auth is externally managed. No speculative initial migration or startup schema reset is included.
