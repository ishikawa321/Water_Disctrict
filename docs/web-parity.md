# Web platform parity

## Current architecture

Staff permissions now follow the confirmed six-part role: office/field work, bill/payment reads and confirmation, all concerns with assigned repairs only, Admin invitations, web/mobile access, and Admin confirmation after Completed. See [Staff setup and permission matrix](staff-role.md). The older audit's Staff financial restrictions and direct Staff resolution are superseded by this change.

Latest synchronization includes upstream main `c44b8bf`: client signup, pending Admin approval, automatic MWD account assignment/linking and refreshed account lists. Manual account creation is replaced by the shared approval operation. Existing billing automation remains intact. See [the current comparison](web-update-comparison.md).

The web is independent of the desktop API. All roles use signed-in Supabase Data API calls to the same project as mobile, with existing RLS. Atomic PostgreSQL functions retain original repair guards, versions, assignment rules, history and rollback. An authorized operator must complete [one-time Supabase office setup](web-supabase-office.md) for Staff access and repair saves. Desktop source is preserved separately and excluded from Vercel. API dependencies in the original audit below are historical.

Audit: 26 November 2026. Base: `feature/desktop-admin-staff` at `68bc1590ce7331fee40598d501ce3e2a94a6d5b1`; mobile main `18bf741` has the same consumer source. Working branch: `feature/web-platform-parity`. Clean clone; original landing page is outside this repository and is preserved. No AGENTS.md was found in the checkout. No live operational writes are used for verification.

Latest follow-up: upstream main `3336607` is now merged. See [app-to-web comparison](web-update-comparison.md) for concern locations, the latest midnight/aqua UI, recent payment activity and payment guidance, and the separate standalone desktop architecture. The original audit below describes the initial parity baseline.

## Source decisions

Inspected `lib/main.dart`, `lib/ui_components.dart`, bundled fonts/license/logo, Desktop App.axaml, MainWindow and workflow/office views and view models, Application contracts, Domain WorkflowRules, API authentication/routes/services, EF workflow service, schema fixture, both reviewed migrations, relevant authorization/office/workflow tests, and the four requested integration/acceptance documents.

The latest sections of live-database-integration.md and acceptance-verification.md supersede their historical pending-migration statements: both reviewed migrations were applied. The API remains authoritative for office workflows. The website does not migrate, reset, provision users, or weaken RLS. Existing mobile legacy office buttons refer personnel to desktop; the web adds another office client with the same permission model.

| Feature | Roles | Mobile | Desktop | Existing support | Web implementation | Discrepancy / acceptance |
|---|---|---|---|---|---|---|
| Sign-in/session/sign-out | All | Active profiles, client/admin; password recovery | Active admin/staff, periodic access checks | Supabase Auth + profiles; API session | Cookie-based SSR, validated user and active profile per request, recovery, role routes | Web supports all three; no signup or role editing exists in supported mobile flow |
| Dashboard | All | Consumer bills, recent concern, notices; admin exact counts | Admin exact counts; Staff quick actions | office/summary; RLS consumer queries | Role dashboards, exact admin counts, refresh | Staff receives no global admin counts |
| Service accounts | Admin; linked client read | Admin list/create; client account profile | List/create | office/accounts; consumer RLS | Existing fields and read-only linked profile | No invented edit/delete/link management |
| Bills | Admin; linked client read | Original amount, verified paid, balance, date-only periods/due date | Same, district-computed entry | office/bills; RLS bills and payment relation | List/create, bill details, decimal-safe totals | No tariff calculation or gateway |
| Offline payments | Admin; linked client read | Verification and bill history | List/create, selected-bill filter | office/payments; consumer RLS | Verification form and bill history | Add API bill-ID filtering if required to avoid filtering only a bounded global list |
| Announcements | Admin; client published read | Prefix-marked interruptions; draft/publish | Same, 150-character stored title | office/announcements; RLS | List/editor, publish/draft, interruption badge | Exact `[Service interruption] ` prefix; marker counts toward 150 |
| Concerns | Admin/Staff office; linked client | Client submit/read; office legacy buttons direct to desktop | Intake/review/close/search/filter | workflow/concerns; RLS consumer submit/read | Intake, review, response, closure, consumer submission/detail | Approved sequential workflow prevails over old flexible mobile forms |
| Dispatch | Admin | Legacy office writer disabled | Reviewed concern only; one ticket | workflow/tickets POST, transactional triggers | Required initial note, expected concern version | Staff/client cannot create tickets |
| Assignment | Admin | Compatibility display text | Active Staff identity, canonical UUID | workflow/assignees and ticket PUT | Active staff picker and required note | Preserve text compatibility field through API |
| Repair updates/history | Admin; own Staff; linked client summary | Saved summary/progress only | Sequential transition, append-only history | workflow/tickets and detail | Role-specific lists, detail, notes, chronological office history | Consumer reads existing saved summaries; no invented live physical tracking |
| Directory | Admin | No Staff model | Active admin/staff listing | admin/staff | Read-only office directory | No user management or public office registration |
| Help/profile | Client | Account number/address/state; authorized-office guidance | N/A | account_access + service_accounts | Linked profile and account/help page | Unlinked account clearly explained |
| Validation/failures | All | Form errors; loaded records retained | Drafts, concurrency, retry ID | API ProblemDetails, xmin, unique ticket, transaction triggers | Accessible errors; retained memory drafts; explicit reload on conflict | No production mock records; no automatic realtime claim |

## List contracts

Office Data API lists: up to 1000. Office workflow concerns/tickets: up to 500 matching records. Office active account lookup: up to 200 matching records with server search. Admin overview uses exact count headers independently. Consumer lists use explicit pagination under their active linked account, with RLS still authoritative. A bounded list never claims to be a district-wide analytical export.

## Phase checklist

- [x] 1. Audit, branch and parity/architecture decisions.
- [x] 2. Next.js foundation, assets and responsive reusable UI.
- [x] 3. Supabase cookie authentication, role boundaries, recovery and access-loss handling.
- [x] 4. Consumer account, billing/payments, concerns/repairs, notices and help.
- [x] 5. Admin management and read-only directory.
- [x] 6. Office concern and repair API workflows, retained drafts and conflicts.
- [x] 7. TypeScript, lint, build, unit/contract and browser verification.
- [x] 8. Vercel frontend publication, shared API hosting instructions and local landing-page handoff.

External acceptance remains separate: deployed HTTPS API URL, Supabase redirect configuration, and authorized application-user cross-platform acceptance. Vercel frontend publication succeeded; GitHub auto-deployment still needs the Vercel Git integration's repository access. No real-user credentials are required for local isolated tests.
