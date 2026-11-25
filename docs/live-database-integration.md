# Verified shared database integration

## Connection and inspection result

On 2026-11-25, the configured Supabase session pooler accepted the saved database credentials with VerifyFull and the downloaded project CA certificate. Read-only inspection and a schema-only public export succeeded. No production row data was imported into tests. Following approval of option 1, the tested migrations were applied to the live database after a verified private backup.

The server runs PostgreSQL 17.11. Before migration, its public schema had eight tables, 68 columns, 51 constraints, 24 RLS policies, 17 indexes and no public row triggers. All eight tables have RLS enabled. Subject and announcement titles are limited to 150 characters. The latter includes the stored service-interruption marker.

The initial metadata report inspected table-level privileges only. The schema export confirmed additional column-level INSERT/UPDATE grants on announcements, repair tickets and service concerns. These are deliberate restrictions and must not be replaced with blanket write grants. The inspector now includes column privileges.

## Confirmed integration gaps

| Current live schema | Desktop requirement / prepared change |
|---|---|
| profiles_role_check permits client and admin only | StaffDirectoryAccess migration adds staff without changing any current profile |
| Users can select only their own active profile | New Admin-only policy permits reading active Admin/Staff directory rows; other users remain restricted to self |
| Ticket assignment is text | RepairWorkflow adds assigned_to_user_id while preserving the consumer-facing text |
| No ticket history or concern dispatch marker | RepairWorkflow adds append-only history and atomic concern/ticket state coordination |
| Concern subject limit 150 | Desktop/API input validation and XAML now use 150 |
| Announcement stored title limit 150 | Validation and UI count the interruption prefix toward the limit |

Existing bill, payment, account and announcement field names match the implemented office modules. The observed verified_at default is now() and profile/account relationships use UUIDs. Service concerns also have nullable latitude, longitude and location_note fields; these are preserved and are not reset by the desktop.

## Prepared migration package

- `20261124154721_RepairWorkflow`: adds assignment ID, dispatch marker, one-ticket constraint, history and shared workflow triggers. Existing tickets receive one explicitly labelled snapshot; earlier events are not fabricated.
- `20261124180709_StaffDirectoryAccess`: extends the profile role constraint and adds the Admin directory policy through a narrowly scoped SECURITY DEFINER helper. It leaves existing consumer policies, profile write restrictions and column-specific write grants intact.
- `desktop/database/repair-workflow.sql`: regenerated idempotent SQL containing both migrations for review.

No users are created, no existing user is promoted to Staff/Admin, and no records are deleted. Existing operational history is protected from automated downgrade. A database backup should precede the live application of these migrations.

## Shared mobile behavior that requires a decision

The latest main mobile draft has Admin ticket forms that write directly to Supabase. Applying the prepared repair triggers will enforce the desktop rules on those writes as well:

1. Review a concern before creating its ticket.
2. Create an Open ticket, then assign an active Staff identity; free-text assignment alone is insufficient.
3. Progress through Assigned, In progress and Resolved, with no reopening of completed tickets.
4. Use the linked repair ticket to update its concern outcome.

Consumer submission and reading remain supported, and the local rehearsal verified their ownership boundary. Choose whether to adopt these shared desktop rules and direct office edits to desktop, or preserve the mobile Admin forms' flexible status behavior and adapt the migration first. The user selected the shared desktop rules (option 1), and both prepared migrations have now been applied.

## Verification against the real schema shape

`desktop/database/verified-public-schema.sql` contains schema-only DDL/grants exported from the actual project, with the public schema creation made repeatable and psql session directives removed. It contains no live table rows. Tests supply local Auth user/uid stubs and generated identities, then apply the actual EF migrations to uniquely named loopback test databases.

The full solution builds with zero warnings and errors. All 83 tests passed, including actual-schema repair processing, Admin-directory visibility, Staff/consumer profile isolation, announcement column grants and immutable creator protection, consumer submission/account isolation, subject-length rejection and interruption-title validation. Existing rollback/concurrency and draft-retention tests also passed. The final readiness policy-marker adjustment was included in that passing suite.

## Live application result

The user approved option 1 on 2026-11-25. A private custom-format backup of the public schema and its records was created and validated by reading the archive without restoring it. Baseline metadata and counts were saved. Both migrations completed successfully, and post-application inspection confirmed:

- 20261124154721_RepairWorkflow and 20261124180709_StaffDirectoryAccess are recorded as applied.
- Existing record counts for all eight original tables are unchanged.
- Ticket history exists, the Staff role is permitted, and the Admin office-directory policy exists.
- Every original consumer policy is preserved.
- No user was created or promoted and no production test records were added.

Private backup and deployment evidence: desktop/artifacts/database-review/deployment-20261125-021820. The archive contains operational data and is intentionally ignored by Git. Keep it private. It is a public-schema/data backup, not a complete export of Supabase Auth or platform infrastructure.

Normal application startup still never migrates or resets data. The database tool's --status mode reads counts and migration IDs in a read-only transaction. --backup-public FILE creates a private archive using pg_dump selected by PG_DUMP_PATH; credentials are passed through the child process environment, not command-line arguments. --export-schema remains schema-only.

Actual Staff login requires a dedicated verified Auth user with an active staff profile. Choose the intended office account explicitly; this deployment does not change a consumer account into Staff automatically. Admin can use the desktop Staff directory after those profiles are provisioned.

## Published runtime check

The fresh self-contained Windows x64 release is desktop/artifacts/release/20261125-022034. Its API was started outside Visual Studio against the live Supabase connection: /health and /health/ready returned 200, while session, workflow and office routes returned 401 without authentication. The published desktop window opened successfully. No production test workflow records were created.

Run launch-local.ps1 in this local release folder to use the existing ignored source API settings. This helper stores only the configuration file path; it contains no password and does not copy the configuration into the package. The launcher temporarily passes the database connection to its API child through the environment and restores the parent environment before opening Desktop. Use launch.ps1 with separate backend configuration when moving the release to another computer.

Remaining verification is sign-in with actual application Admin/Staff credentials and a real authorized workflow demonstration. A Supabase Dashboard/GitHub login or the database password is not an application user login.
