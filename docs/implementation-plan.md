# Water District desktop implementation plan

The Admin and Staff desktop application shares the consumer app's Supabase PostgreSQL database. Development takes place on `feature/desktop-admin-staff`; the Flutter app stays at the repository root. Commit and push completed additions after verification.

## Scope

Workflow 1 receives, validates, and reviews service concerns, including office reports. Workflow 2 creates a repair ticket from an eligible concern, assigns active staff, and records progress and resolution. A concern can close without a repair ticket when no repair is required.

Advanced capability A coordinates ticket creation, its first history event, and the concern's processing state in one transaction. Success and rollback must be verified against PostgreSQL.

The desktop uses C#/.NET, Avalonia/XAML, MVVM, dependency injection, asynchronous services, an ASP.NET Core API, and EF Core with PostgreSQL. Supabase Auth supplies identity. The API checks active database profiles and permissions. Consumer Data API requests remain subject to RLS. Database credentials belong only in backend configuration.

## Sessions

| Session | Deliverable | Completion condition |
|---|---|---|
| 1 | Repository branch, reconciliation draft, implementation plan | Baseline and proposed boundaries documented; instructor approval left pending |
| 2 | Database inventory, proposed ERD, migration strategy | Observed facts separated from source assumptions; live constraints verified when authorized PostgreSQL access is available |
| 3 | Avalonia solution, layers, API, DI, EF Core foundation, tests | Solution builds; desktop opens; health and dependency checks behave honestly |
| 4 | Supabase sign-in, active Admin/Staff authorization, role-aware workspace | Protected API rejects unauthenticated, inactive and consumer users; provisioning documented |
| 5 | Concern intake and account lookup | Valid concern persists; failed save retains draft |
| 6 | Review decisions and no-repair closure | Review outcome is durable and visible to the consumer |
| 7 | Transactional ticket creation | Ticket, initial history and concern state commit or roll back together |
| 8 | Staff assignment, progress, resolution and history | Authorized transitions succeed; invalid/conflicting updates fail |
| 9 | Mobile compatibility | Consumer submission travels through desktop processing and back to consumer visibility |
| 10 | Acceptance scenarios and automated verification | Required coverage and actual results recorded |
| 11 | Self-contained Windows x64 release | Published desktop and API run outside Visual Studio with documented dependencies |
| 12 | Submission and demonstration | Approved scope, ERD, source, tests, README, verification record and 8–10 minute demonstration ready |

Each session is approximately 2–3 hours; database access and release preparation may require additional blocks. The database is shared across Git branches, so schema changes are first rehearsed in a disposable development environment.

## Sources

- Local ITSD81 Final Project Handout and Testing Guide, version 1.2, instructor review candidates.
- `Malnegro&Tanamal_Midterm_Presentation (2).pptx`, slides 1–11.
- Existing Flutter source at repository baseline `d8a48e419e636310c23de8a9c864de434e61d9f0`.

The original assessment PDFs and presentation remain local. This repository records the derived implementation documentation.

## Implementation status on 2026-11-25

Sessions 5?8 are implemented: concern intake/review, no-repair closure, transactional ticket creation, Staff assignment, progress/resolution, history and conflicts. Session 9 preserves consumer query fields and sends legacy mobile office edits to desktop; local SQL ownership/submission tests pass, while live Supabase integration remains pending access. Session 10 has 55 passing .NET tests and 14 passing Flutter tests with actual results in acceptance-verification.md. Session 11 has published and smoke-checked self-contained Windows x64 executables. Session 12 has the ERD, README, acceptance record, release checklist and demonstration script prepared; instructor approval, confirmed IDs and the actual demonstration remain human/environment deliverables.
