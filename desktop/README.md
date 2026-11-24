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
