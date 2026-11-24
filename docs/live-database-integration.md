# Verified shared database integration

## Connection and inspection result

On 2026-11-25, the configured Supabase session pooler accepted the saved database credentials with VerifyFull and the downloaded project CA certificate. Read-only inspection and a schema-only public export succeeded. No production row data was imported into tests, and no migration or operational write has been applied to the live database.

The server runs PostgreSQL 17.11. Its public schema has eight tables, 68 columns, 51 constraints, 24 RLS policies, 17 indexes and no public row triggers. All eight tables have RLS enabled. Subject and announcement titles are limited to 150 characters. The latter includes the stored service-interruption marker.

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

Consumer submission and reading remain supported, and the local rehearsal verified their ownership boundary. Choose whether to adopt these shared desktop rules and direct office edits to desktop, or preserve the mobile Admin forms' flexible status behavior and adapt the migration first. Live migration is pending that workflow choice.

## Verification against the real schema shape

`desktop/database/verified-public-schema.sql` contains schema-only DDL/grants exported from the actual project, with the public schema creation made repeatable and psql session directives removed. It contains no live table rows. Tests supply local Auth user/uid stubs and generated identities, then apply the actual EF migrations to uniquely named loopback test databases.

The full solution builds with zero warnings and errors. All 83 tests passed, including actual-schema repair processing, Admin-directory visibility, Staff/consumer profile isolation, announcement column grants and immutable creator protection, consumer submission/account isolation, subject-length rejection and interruption-title validation. Existing rollback/concurrency and draft-retention tests also passed. The final readiness policy-marker adjustment was included in that passing suite.

## Apply after the workflow decision

Use the saved local PostgreSQL configuration to create a backup, then run the database tool with --migrate explicitly. Normal application startup never migrates or resets data. Inspect the resulting schema and /health/ready afterward. Actual Staff login additionally requires an authorized operator to link an existing verified Auth user to an active staff profile; this migration does not pick a user automatically.
