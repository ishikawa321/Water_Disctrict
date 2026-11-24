# Windows release and demonstration

The release contains separate self-contained Windows x64 Desktop, Api and Database folders. Keep all native libraries, assets and configuration. A .NET runtime installation is not required. PostgreSQL and Supabase Auth are external dependencies and are not bundled.

## Prepare the shared environment

1. Inspect the existing Supabase schema with the Database executable (default mode) and a backend PostgreSQL connection. Review the schema contract and back up the database.
2. Rehearse the migration on a development copy. Its preflight rejects incompatible column types, existing workflow triggers/history and duplicate tickets. Reconcile differences rather than removing safeguards.
3. Run `Database/WaterDistrict.Database.exe --migrate` against the reviewed database. Migrations never run on application startup. `--bootstrap-development` is limited to loopback databases named `waterdistrict_dev...` and creates no operational records.
4. Check existing RLS prevents consumer role escalation and limits account data to its owner. Extend the existing profile role constraint/enum to include Staff through a reviewed change if required. The migration does not guess that live constraint.
5. Configure `Api/appsettings.Local.json` after publishing or set backend environment configuration. Keep database credentials out of Desktop settings. Configure the public API address in Desktop settings when using a separately hosted API.
6. Use dedicated verified Auth users with active Admin, Staff and Client profiles, a service account, and the correct consumer account link. Record stakeholder/instructor approval separately.

## Build and launch

Run `desktop/scripts/publish.ps1` from source. It creates a new timestamped folder under `desktop/artifacts/release/`, containing self-contained executables, documentation, a launcher and SHA256 checksums. Existing output is never overwritten and local configuration overrides are excluded.

Run `launch.ps1` in a release folder to start the loopback API on port 5181 and open the desktop. When that desktop closes, the launcher stops its API process. Run only one local launcher at a time. For a separately hosted API, configure its HTTPS URL and open the Desktop executable directly. To start the API independently, run `WaterDistrict.Api.exe --urls http://127.0.0.1:5181` from the Api folder.

`/health` checks process liveness. `/health/ready` checks database reachability and workflow schema markers, returning 503 for unconfigured/unavailable/unmigrated environments. A ready result does not replace acceptance verification.

## Manual release checklist

| Check | Expected result |
|---|---|
| Open outside Visual Studio | Sign-in screen, logo and readable controls load without a .NET installation |
| Admin / Staff / Client sign-in | Admin and Staff enter their permitted workspace; consumer desktop access is denied |
| Valid office concern | Saved report appears after refresh with accountable identity and time |
| Missing description | Useful rejection, no saved record, draft retained |
| Review and create repair ticket | Linked ticket, first Open event and concern dispatch marker commit together |
| Assign and progress as Staff | Assigned staff records In progress then Resolved with notes and history |
| Refresh consumer app | Correct account sees the same saved summary and resolution; other accounts cannot see it |
| Close and reopen desktop/API | Records, assignment and history remain |
| Disconnect dependency | Truthful failure feedback, retained draft and refresh before retry |
| Tests with local PostgreSQL | Unit, API, UI and relational tests pass; retain TRX evidence |

Record actual shared-environment results. Local automated checks do not establish live Supabase integration.

## Demonstration script

Plan 8?10 minutes:

- Minute 0?1: launch the published app outside Visual Studio; explain the three roles and shared database.
- Minute 1?3: receive a concern, show missing-field rejection and successful save, then review it.
- Minute 3?5: Admin creates one ticket and assigns Staff; show concern link and history.
- Minute 5?7: Staff records progress and resolution; refresh the consumer app to show the same outcome.
- Minute 7?8: restart and reopen records; show stale-update or invalid-transition handling.
- Minute 8?10: show xUnit evidence for rollback/concurrency, ERD, configuration and dependency handling.

Updates record personnel actions and do not automatically monitor physical repairs. Each member should explain MVVM, API authorization, EF Core, record versions and database transaction/history rules.

## Submission checklist

- Source solution and consumer compatibility changes.
- Approved scope reconciliation sheet, confirmed members/student IDs and approved architecture.
- Updated ERD, migration source and reproducible initialization instructions.
- Acceptance scenarios, xUnit project and actual verification record.
- Self-contained Windows x64 release folders and checksum manifest.
- README for configuration, migrations, tests, launch, dependencies and limitations.

Instructor approval, actual office-user provisioning and live consumer-to-desktop verification require the shared environment and authorized identities. These cannot be certified by local tests alone.

## Current local deployment

The approved workflow/Staff migrations are now installed in Supabase. Local release desktop/artifacts/release/20261125-022034 passed native startup, live database readiness (HTTP 200) and anonymous-access rejection checks. launch-local.ps1 uses the ignored source API configuration by file path without embedding its credentials. A complete real-user Admin/Staff demonstration still requires the intended application accounts. See live-database-integration.md for the private backup location and preservation checks.
