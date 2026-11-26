# Maramag Water District service desk

Current implementation boundary: **Phase 2 - account-linked concerns**. The existing Avalonia/.NET 10 solution, PostgreSQL configuration, authentication, persisted permissions and shared design resources are reused. The separate Flutter application is untouched. All demonstration identities and customer data are fictional.

Run the current source; historical executables under `artifacts/` may contain earlier workflows and are not Phase 2 delivery builds.

## Start and migrate

On this configured machine, start the existing isolated PostgreSQL cluster if stopped (does not reset data):

```powershell
& 'C:/Program Files/PostgreSQL/18/bin/pg_ctl.exe' start -D '.local/postgres' -l '.local/postgres.log' -o '-h 127.0.0.1 -p 55481' -w
./scripts/Start-Phase2.ps1 -UseExistingLocalDemo -Migrate
```

On subsequent launches use `./scripts/Start-Phase2.ps1 -UseExistingLocalDemo`. For another authorized PostgreSQL database, configure `MWD_CONNECTION` in the process environment, or `appsettings.local.json` beside the executable using `appsettings.example.json`. Enable `MWD_DEMO=true` only for fictional demo seeding. Then run `./scripts/Start-Phase2.ps1 -Migrate`. The script disables optional operational sample seeding. Ordinary startup checks schema readiness and does not migrate or reset data.

The forward migration `20261123160835_Phase2Concerns` preserves existing concerns, identities, events, references and repair relationships. It adds event state/category history, an idempotent submission key, supported intake channels and a PostgreSQL reference sequence. Original intake text is preserved in `LegacyIntakeChannel`. EF tools can also apply it with `dotnet ef database update --project WaterDistrictConnect.Core`. Do not roll back or delete existing migrations. Phase 2 intentionally refuses destructive downgrade.

Keep local configuration and `.local/demo-settings.json` private. The application reports missing configuration, pending migrations and unavailable PostgreSQL at sign-in. There is no fallback database.

## Working concern workflow

Clients submit using their linked account, with category, subject, description, prefilled service location and optional contact details. Application services independently validate required fields, lengths and ownership. Receipt, initial event and audit commit in one transaction. PostgreSQL generates unique human-readable references; a per-form submission key prevents duplicate saves when a successful response is lost and retried.

My Concerns and the office Concern Queue support search, category/status filters, clear filters, pagination and refresh. Details show the current state, intake attribution, first human response and chronological history. Clients only receive their own records and customer-visible events. Internal notes and classification/review reasons are filtered before DTO creation.

Authorized handlers can review, add customer-visible responses, record internal notes, correct classification with a reason, resolve/close eligible nontechnical concerns, and reopen with a reason. Closure and reopening require confirmation. Office intake searches existing fictional accounts and records the actual Telephone, Walk-in or Other channel and recording user. Read-only personnel cannot mutate records even through direct service calls.

Technical concerns remain Submitted or Under Review while awaiting Phase 3. They cannot be manually moved to Awaiting Repair or resolved/closed through this phase. Classification correction is for factual intake mistakes, with retained reasons; it must not be used to relabel an actual repair need merely to close it. Repair-ticket creation and updates are disabled in services and navigation. Existing ticket relationships/data are preserved for Phase 3 review.

Only the explicit customer-visible **response** action starts the first-human-response clock. Receipt, opening a detail, review, classification, internal notes and lifecycle reasons do not count as a response. Later responses retain the original timestamp. Dates persist in UTC and display in Philippine Time (PHT, UTC+08:00).

## Fictional demo logins

All seven demo users use `WaterDemo!2026`; salted ASP.NET Identity hashes are stored.

| Username | Access | Account |
| --- | --- | --- |
| admin | Concern intake and handling | Office |
| handler | Concern intake and handling | Office |
| viewer | Read-only office records | Office |
| coordinator | Read-only concerns in Phase 2; repair processing deferred | Office |
| amara | Client A, own records | 000101 |
| benito | Client B, own records | 000102 |
| clara | Client, own records | 000103 |

## Verification

```powershell
dotnet build -c Release
./scripts/Test-Phase2.ps1 -UseExistingLocalDemo
dotnet ef migrations has-pending-model-changes --project WaterDistrictConnect.Core
```

For a dedicated external test server, set `MWD_TEST_ADMIN` to a connection authorized to create/drop disposable databases and omit `-UseExistingLocalDemo`. Phase 2 tests migrate/seed only generated `mwd_phase2_<GUID>` databases and drop only those generated names. They never clean/reset the application database. The script refuses an absent test connection; direct xUnit runs explicitly skip PostgreSQL tests when no test connection exists.

See [Phase 2 verification and demonstration](docs/Phase2.md), [architecture](docs/Architecture.md), [ERD](docs/ERD.md) and the historical [Phase 1 record](docs/Phase1.md). Source projects separate presentation/MVVM, application services, domain policy and persistence. Package versions and lock files are retained.

## Manual demonstration

1. Sign in as **amara**, open Submit Concern, choose General Inquiry, enter a fictional subject/description, select Review concern and submit. Note the `MWD-...` reference and automatic receipt explanation; select View saved concern.
2. Sign out and sign in as **handler**.
3. Open Concern Queue, search the saved reference, select View, choose Customer-visible response, enter at least 10 characters and save.
4. Sign out, return as **amara**, open My Concerns and verify Under Review, the response and first-human-response time.
5. Sign in as **benito** and search the same reference: no record is returned. Direct foreign detail/account calls are additionally covered by integration tests.
6. Close/restart the current application, sign in as **amara** and open the reference again; the response and history remain in PostgreSQL.

## Limitations and Phase 3 boundary

This is a trusted-machine fictional-data desktop prototype. Production service isolation, provisioning, password recovery, backups UI, payments and live district integration are outside this phase. Database credentials permit database-level access and must be protected. No repair processing is enabled. Phase 3 must integrate the reserved Awaiting Repair transition with the retained one-concern/one-ticket relationship, version checks and history rather than exposing arbitrary state selection.

No instructor approval, district validation, operational response guarantee or research participant results are claimed. Native accessibility, display scaling and full keyboard review remain broader UI verification work; see the exact executed checks in the Phase 2 record.

The desktop UI now follows the supplied client/admin reference boards across all working Phase 2 screens. See [UI reference alignment and rendered previews](docs/UIReferenceAlignment.md). Regenerate development screenshots with `./scripts/Review-UI.ps1 -UseExistingLocalDemo`; this uses disposable PostgreSQL fixtures and the actual production views, outside the application solution.
