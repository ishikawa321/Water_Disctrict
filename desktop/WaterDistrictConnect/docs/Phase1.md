# Phase 1 foundation

Historical Phase 1 implementation record. The current implementation boundary is now Phase 2; see [Phase 2 verification](Phase2.md) and the current README. Results below describe the earlier foundation review and are preserved as historical evidence.

Current phase boundary: foundation, PostgreSQL, identity, authentication and application shell. Work stops here for review before Phase 2.

## Workspace assessment

The existing Avalonia solution at `C:\Users\steve\Documents\WaterDistrictConnect\WaterDistrictConnect` was reused. No duplicate desktop solution was created. Its Core, desktop, unit-test and integration-test projects already separate presentation, ViewModels, domain rules, services, authentication and EF persistence.

The reference at `C:\malnegro_activities\MAD FINALS\water_district_connect` is a separate Flutter project (its directory structure and pubspec were inspected read-only). It was not overwritten, converted, deleted, or changed. No applicable AGENTS.md was found in the desktop workspace or its ancestor directories.

Earlier workflow implementations and their migration tables were already present in the desktop project. They are preserved rather than deleted or rolled back. The default application shell now exposes only working Phase 1 destinations: Overview and My Account for clients; Overview, Customer Accounts and Plumber Resources for office roles. Related concern/ticket panels and direct workflow navigation are disabled in the Phase 1 shell. No new concern or repair workflow is delivered or accepted by this phase.

## Implemented foundation

The application uses DI, async EF PostgreSQL access, individual demo identities, stored role/permission relationships, one linked fictional account per client and fictional plumber resources. Existing `InitialScope` migration and its snapshot are retained; it includes the foundation plus previously implemented workflow tables. No destructive migration was introduced.

Passwords use the maintained ASP.NET Identity PasswordHasher implementation with salted PBKDF2 hashes. The known demo password is an explicit fictional demo credential, not plaintext database storage. Seeding runs only when DemoMode is enabled, preserves existing users/hashes/ownership and operational records, and serializes competing seed runs with a PostgreSQL transaction lock. Phase 1 launch scripts disable optional operational sample seeding.

Authentication validates input before database access, checks active status, loads persisted roles/permissions and clears the session on failed login. Protected services reread active identity and permissions. Logout clears the session and discards the workspace and entered password. Customer-account reads enforce ownership in the service query; clients cannot read plumber resources. Database configuration is validated only when an operation executes, allowing the login screen to show actionable feedback instead of crashing on startup. No operational database fallback is configured.

Overview displays the signed-in role and actual saved reference information, not invented workflow activity. Accounts are read-only, searchable for office users and scoped to the client's ownership. Shell styling retains the shared blue palette, Segoe UI, vector icons, keyboard focus states and restrained motion from the earlier UI refresh.

## Run this phase

On the current machine, the previously configured loopback PostgreSQL server is available on port 55481. This command uses its existing ignored credentials without installing a server, changing credentials, or modifying services:

```powershell
./scripts/Start-Phase1.ps1 -UseExistingLocalDemo
```

This runs the current source, rather than an older published artifact. Existing `artifacts/win-x64*` directories are historical builds and should not be used to assess the Phase 1 shell. Final self-contained publishing remains Phase 5.

For another authorized PostgreSQL database, set `MWD_CONNECTION` in your process environment or copy `appsettings.example.json` to `appsettings.local.json` beside the application executable. Keep credentials outside source control. Set `MWD_DEMO=true` explicitly to seed the fictional reference dataset. Run `./scripts/Start-Phase1.ps1 -Migrate` for intentional initialization, then use `./scripts/Start-Phase1.ps1` on later launches. The script does not start, install, or reconfigure PostgreSQL. Ordinary startup checks migrations and reports pending initialization rather than deleting/resetting records.

| Username | Persisted role | Account |
| --- | --- | --- |
| admin | Administrator (intake, response and coordination privileges) | Office |
| handler | Concern handler | Office |
| coordinator | Ticket coordinator | Office |
| viewer | Office viewer (read-only) | Office |
| amara | Client | 000101 |
| benito | Client | 000102 |
| clara | Client | 000103 |

Password for all seven fictional demo users: `WaterDemo!2026`. The existing permission matrix and exact package versions are in `docs/Architecture.md`; explicit package references and committed NuGet lock files provide reproducible resolution.

## Verification executed

```powershell
dotnet build -c Release
./scripts/Test-Phase1.ps1 -UseExistingLocalDemo
```

| Check | Actual result |
| --- | --- |
| Release build | Passed; 0 warnings, 0 errors |
| Locked dependency restore | `dotnet restore --locked-mode` passed for all four projects |
| EF model/migration consistency | `dotnet ef migrations has-pending-model-changes --project WaterDistrictConnect.Core` reported no model changes since the last migration |
| Phase 1 unit tests | 11 passed, 0 failed, 0 skipped |
| Phase 1 real PostgreSQL integration tests | 6 passed, 0 failed, 0 skipped |
| Migration discovery | Existing `20261123143321_InitialScope` found |
| Initial migration applied on dedicated test database | Passed as part of integration setup |
| Seven identities / three distinct client accounts | Passed against PostgreSQL |
| Wrong password, unknown user, inactive user | Rejected; no authenticated session retained |
| Active session after user deactivation | Protected account service rejected access |
| Login and logout through root ViewModel | Passed against PostgreSQL; workspace discarded and later service call rejected |
| Seeding twice after existing reference/operational data | Passed; IDs, hashes, ownership and preserved concern unchanged |
| Password storage | Persisted values are hashes, do not contain demo plaintext; salted hash and incorrect-password rejection also tested |
| Missing configuration | Unit test exercised login ViewModel; clear MWD_CONNECTION guidance, input preserved, busy flag restored |
| Malformed connection configuration | Rejected without disclosing its secret contents |
| Unavailable PostgreSQL | Real port-1 connection attempt exercised login ViewModel; connection feedback displayed in VM, input retained, busy flag restored |
| Duplicate operation guard | Unit test confirmed a concurrent submission is ignored and loading recovers after failure |
| Phase 1 navigation | Unit test confirms only implemented foundation destinations and rejects direct later-workflow navigation |
| Native-window client login | Amara signed in against the existing demo PostgreSQL database; Overview and My Account were the only sidebar destinations |
| Native-window account screen | Displayed account 000101, fictional name/address and username; no concern/ticket panels or edit controls |
| Native-window logout | Returned to login with empty username/password inputs and no previous workspace |

Raw results: `TestResults/phase1-unit.trx` and `TestResults/phase1-postgresql.trx`. The test script filters `Phase=1`. The dedicated `mwd_phase1_test` database is retained; tests never drop a database, reset normal records, or clean the application database. Each inactive-user fixture has a unique fictional identity. Legacy later-phase integration tests require a separate explicit database-deletion opt-in and were not run for Phase 1.

Automated UI-state tests are distinct from native-window/manual checks. Native client login, account inspection and logout were executed. Error messages and office-role decisions were exercised through automated ViewModel/service checks; a full native-window office-role and failure matrix was not executed. This phase does not claim a complete keyboard, scaling or screen-reader audit. Phase 4 and Phase 5 checks remain outstanding.

## Evidence and pending review

Course requirements and manuscript context remain distinguished in `docs/Requirements.md`. The client desktop experience is a proposed adaptation of the broader web manuscript. Actual Midterm details and membership require verification; the second requested scope reconciliation document remains unavailable. Instructor approval is pending. No district duties, production integration, signatures, or research participant results are asserted.

There is no database blocker on this machine. Other machines require an authorized reachable PostgreSQL database and local connection configuration. The known demo credentials are deliberately limited to fictional development data.

## Next phase

After Phase 1 acceptance, Phase 2 will review and enable client concern submission, office intake, classification and human response, account-scoped lists/details, internal-note filtering, first-response timestamps and persistent concern history, with focused service and PostgreSQL tests. Repair processing, end-to-end UI review and final delivery remain later phase boundaries.
